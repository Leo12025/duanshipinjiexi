#!/usr/bin/env python3
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE_ROOT = ROOT / "ShortsLibrary"
PROJECT_DIR = ROOT / "ShortsLibrary.xcodeproj"
WORKSPACE_DIR = PROJECT_DIR / "project.xcworkspace"


def ident(name: str) -> str:
    return hashlib.sha1(name.encode("utf-8")).hexdigest()[:24].upper()


swift_files = sorted(
    str(path.relative_to(ROOT)) for path in SOURCE_ROOT.rglob("*.swift")
)
TEST_ROOT = ROOT / "ShortsLibraryTests"
test_swift_files = sorted(
    str(path.relative_to(ROOT)) for path in TEST_ROOT.rglob("*.swift")
) if TEST_ROOT.exists() else []
asset_path = "ShortsLibrary/Assets.xcassets"
localization_path = "ShortsLibrary/zh-Hans.lproj"
privacy_path = "ShortsLibrary/PrivacyInfo.xcprivacy"
info_path = "ShortsLibrary/Info.plist"
product_path = "ShortsLibrary.app"

objects: dict[str, dict] = {}


def add(object_id: str, **fields) -> None:
    objects[object_id] = fields


PRESERVED_KEYS = (
    "DEVELOPMENT_TEAM",
    "PRODUCT_BUNDLE_IDENTIFIER",
    "CODE_SIGN_STYLE",
    "PROVISIONING_PROFILE_SPECIFIER",
)


def load_existing_settings() -> dict[tuple[str, str], dict]:
    path = PROJECT_DIR / "project.pbxproj"
    if not path.exists():
        return {}
    try:
        raw = subprocess.check_output(
            ["plutil", "-convert", "json", "-o", "-", str(path)],
            stderr=subprocess.DEVNULL,
        )
        data = json.loads(raw)
        existing = data["objects"]
        root = existing[data["rootObject"]]
    except (OSError, subprocess.CalledProcessError, KeyError, json.JSONDecodeError):
        return {}

    def settings_of(config_list_id: str) -> dict[str, dict]:
        result = {}
        config_list = existing.get(config_list_id, {})
        for config_id in config_list.get("buildConfigurations", []):
            config = existing.get(config_id, {})
            name = config.get("name")
            if not name:
                continue
            result[name] = {
                key: value
                for key, value in config.get("buildSettings", {}).items()
                if key in PRESERVED_KEYS and value not in ("", None)
            }
        return result

    preserved = {}
    for name, settings in settings_of(root.get("buildConfigurationList")).items():
        preserved[("__project__", name)] = settings
    for target_id in root.get("targets", []):
        target = existing.get(target_id, {})
        target_name = target.get("name")
        if not target_name:
            continue
        for name, settings in settings_of(target.get("buildConfigurationList")).items():
            preserved[(target_name, name)] = settings
    return preserved


def apply_preserved(
    target_name: str, config_name: str, settings: dict, preserved: dict
) -> None:
    for key in PRESERVED_KEYS:
        value = preserved.get((target_name, config_name), {}).get(key)
        if value not in (None, ""):
            settings[key] = value


existing_settings = load_existing_settings()

project_id = ident("object:project")
main_group = ident("object:group.main")
sources_group = ident("object:group.sources")
products_group = ident("object:group.products")
target_id = ident("object:target")
product_ref = ident("file:" + product_path)
sources_phase = ident("phase:sources")
frameworks_phase = ident("phase:frameworks")
resources_phase = ident("phase:resources")
project_cfg_list = ident("configlist:project")
target_cfg_list = ident("configlist:target")
project_debug = ident("config:project.debug")
project_release = ident("config:project.release")
target_debug = ident("config:target.debug")
target_release = ident("config:target.release")
test_group = ident("object:group.tests")
test_target_id = ident("object:target.tests")
test_product_path = "ShortsLibraryTests.xctest"
test_product_ref = ident("file:" + test_product_path)
test_sources_phase = ident("phase:tests.sources")
test_frameworks_phase = ident("phase:tests.frameworks")
test_cfg_list = ident("configlist:tests")
test_debug = ident("config:tests.debug")
test_release = ident("config:tests.release")
xctest_ref = ident("file:XCTest.framework")
xctest_build = ident("build:XCTest.framework")
app_product_test_build = ident("build:app.product.for.tests")
target_dependency_id = ident("dependency:tests.to.app")
container_proxy_id = ident("proxy:tests.to.app")

SOURCE_DIR_NAME = SOURCE_ROOT.name
TEST_DIR_NAME = TEST_ROOT.name
group_registry: dict[tuple[str, str], str] = {}


def nested_group(parent_id: str, parts: tuple[str, ...]) -> str:
    current = parent_id
    for part in parts:
        key = (current, part)
        child_id = group_registry.get(key)
        if child_id is None:
            child_id = ident(f"group:{current}:{part}")
            add(
                child_id,
                isa="PBXGroup",
                children=[],
                name=part,
                path=part,
                sourceTree="<group>",
            )
            objects[current]["children"].append(child_id)
            group_registry[key] = child_id
        current = child_id
    return current


add(
    main_group,
    isa="PBXGroup",
    children=[sources_group, test_group, products_group],
    sourceTree="<group>",
)
add(
    sources_group,
    isa="PBXGroup",
    children=[],
    name=SOURCE_DIR_NAME,
    path=SOURCE_DIR_NAME,
    sourceTree="<group>",
)
add(
    test_group,
    isa="PBXGroup",
    children=[],
    name=TEST_DIR_NAME,
    path=TEST_DIR_NAME,
    sourceTree="<group>",
)
add(
    products_group,
    isa="PBXGroup",
    children=[product_ref, test_product_ref],
    name="Products",
    sourceTree="<group>",
)

source_ids = []
test_source_ids = []
resource_ids = []

for rel in swift_files:
    ref = ident("file:" + rel)
    build = ident("build:" + rel)
    rel_path = Path(rel).relative_to(SOURCE_DIR_NAME)
    add(
        ref,
        isa="PBXFileReference",
        lastKnownFileType="sourcecode.swift",
        path=rel_path.name,
        sourceTree="<group>",
    )
    add(build, isa="PBXBuildFile", fileRef=ref)
    source_ids.append(build)
    parent = nested_group(sources_group, rel_path.parent.parts)
    objects[parent]["children"].append(ref)

for rel in test_swift_files:
    ref = ident("file:" + rel)
    build = ident("build:" + rel)
    rel_path = Path(rel).relative_to(TEST_DIR_NAME)
    add(
        ref,
        isa="PBXFileReference",
        lastKnownFileType="sourcecode.swift",
        path=rel_path.name,
        sourceTree="<group>",
    )
    add(build, isa="PBXBuildFile", fileRef=ref)
    test_source_ids.append(build)
    parent = nested_group(test_group, rel_path.parent.parts)
    objects[parent]["children"].append(ref)

asset_ref = ident("file:" + asset_path)
asset_build = ident("build:" + asset_path)
add(
    asset_ref,
    isa="PBXFileReference",
    lastKnownFileType="folder.assetcatalog",
    path=Path(asset_path).name,
    sourceTree="<group>",
)
add(asset_build, isa="PBXBuildFile", fileRef=asset_ref)
resource_ids.append(asset_build)
objects[sources_group]["children"].append(asset_ref)

localization_group = ident("variant:Localizable.strings")
localization_ref = ident("file:" + localization_path + "/Localizable.strings")
localization_build = ident("build:" + localization_path + "/Localizable.strings")
add(
    localization_group,
    isa="PBXVariantGroup",
    name="Localizable.strings",
    sourceTree="<group>",
    children=[localization_ref],
)
add(
    localization_ref,
    isa="PBXFileReference",
    lastKnownFileType="text.plist.strings",
    name="zh-Hans",
    path=str(Path(localization_path) / "Localizable.strings"),
    sourceTree="<group>",
)
add(localization_build, isa="PBXBuildFile", fileRef=localization_group)
resource_ids.append(localization_build)
objects[sources_group]["children"].append(localization_group)

privacy_ref = ident("file:" + privacy_path)
privacy_build = ident("build:" + privacy_path)
add(
    privacy_ref,
    isa="PBXFileReference",
    lastKnownFileType="text.plist.xml",
    path=Path(privacy_path).name,
    sourceTree="<group>",
)
add(privacy_build, isa="PBXBuildFile", fileRef=privacy_ref)
resource_ids.append(privacy_build)
objects[sources_group]["children"].append(privacy_ref)

info_ref = ident("file:" + info_path)
add(
    info_ref,
    isa="PBXFileReference",
    lastKnownFileType="text.plist.xml",
    path=Path(info_path).name,
    sourceTree="<group>",
)
objects[sources_group]["children"].append(info_ref)

add(
    product_ref,
    isa="PBXFileReference",
    explicitFileType="wrapper.application",
    includeInIndex="0",
    path=product_path,
    sourceTree="BUILT_PRODUCTS_DIR",
)

add(
    test_product_ref,
    isa="PBXFileReference",
    explicitFileType="wrapper.cfbundle",
    includeInIndex="0",
    path=test_product_path,
    sourceTree="BUILT_PRODUCTS_DIR",
)
add(
    xctest_ref,
    isa="PBXFileReference",
    lastKnownFileType="wrapper.framework",
    name="XCTest.framework",
    path="System/Library/Frameworks/XCTest.framework",
    sourceTree="SDKROOT",
)
add(xctest_build, isa="PBXBuildFile", fileRef=xctest_ref)
add(app_product_test_build, isa="PBXBuildFile", fileRef=product_ref)

add(
    frameworks_phase,
    isa="PBXFrameworksBuildPhase",
    buildActionMask="2147483647",
    files=[],
    runOnlyForDeploymentPostprocessing="0",
)
add(
    sources_phase,
    isa="PBXSourcesBuildPhase",
    buildActionMask="2147483647",
    files=source_ids,
    runOnlyForDeploymentPostprocessing="0",
)
add(
    resources_phase,
    isa="PBXResourcesBuildPhase",
    buildActionMask="2147483647",
    files=resource_ids,
    runOnlyForDeploymentPostprocessing="0",
)

add(
    test_sources_phase,
    isa="PBXSourcesBuildPhase",
    buildActionMask="2147483647",
    files=test_source_ids,
    runOnlyForDeploymentPostprocessing="0",
)
add(
    test_frameworks_phase,
    isa="PBXFrameworksBuildPhase",
    buildActionMask="2147483647",
    files=[xctest_build, app_product_test_build],
    runOnlyForDeploymentPostprocessing="0",
)
add(
    container_proxy_id,
    isa="PBXContainerItemProxy",
    containerPortal=project_id,
    proxyType=1,
    remoteGlobalIDString=target_id,
    remoteInfo="ShortsLibrary",
)
add(
    target_dependency_id,
    isa="PBXTargetDependency",
    target=target_id,
    targetProxy=container_proxy_id,
)

add(
    target_id,
    isa="PBXNativeTarget",
    buildConfigurationList=target_cfg_list,
    buildPhases=[sources_phase, frameworks_phase, resources_phase],
    buildRules=[],
    dependencies=[],
    name="ShortsLibrary",
    productName="ShortsLibrary",
    productReference=product_ref,
    productType="com.apple.product-type.application",
)

add(
    test_target_id,
    isa="PBXNativeTarget",
    buildConfigurationList=test_cfg_list,
    buildPhases=[test_sources_phase, test_frameworks_phase],
    buildRules=[],
    dependencies=[target_dependency_id],
    name="ShortsLibraryTests",
    productName="ShortsLibraryTests",
    productReference=test_product_ref,
    productType="com.apple.product-type.bundle.unit-test",
)

common_settings = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "ENABLE_PREVIEWS": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": info_path,
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.leo.shortslibrary",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SDKROOT": "iphoneos",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1,2",
}

debug_settings = dict(common_settings)
debug_settings.update(
    {
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }
)

release_settings = dict(common_settings)
release_settings.update(
    {
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
        "VALIDATE_PRODUCT": "YES",
    }
)

for target_name, config_name, settings in [
    ("__project__", "Debug", debug_settings),
    ("__project__", "Release", release_settings),
    ("ShortsLibrary", "Debug", debug_settings),
    ("ShortsLibrary", "Release", release_settings),
]:
    apply_preserved(target_name, config_name, settings, existing_settings)

test_overrides = {
    "GENERATE_INFOPLIST_FILE": "YES",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.leo.shortslibrary.tests",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/ShortsLibrary.app/ShortsLibrary",
    "BUNDLE_LOADER": "$(TEST_HOST)",
}
test_debug_settings = dict(debug_settings)
test_debug_settings.update(test_overrides)
test_release_settings = dict(release_settings)
test_release_settings.update(test_overrides)

for config_name, settings in [
    ("Debug", test_debug_settings),
    ("Release", test_release_settings),
]:
    apply_preserved("ShortsLibraryTests", config_name, settings, existing_settings)

for config_id, name, settings in [
    (project_debug, "Debug", debug_settings),
    (project_release, "Release", release_settings),
    (target_debug, "Debug", debug_settings),
    (target_release, "Release", release_settings),
    (test_debug, "Debug", test_debug_settings),
    (test_release, "Release", test_release_settings),
]:
    add(config_id, isa="XCBuildConfiguration", buildSettings=settings, name=name)

add(
    project_cfg_list,
    isa="XCConfigurationList",
    buildConfigurations=[project_debug, project_release],
    defaultConfigurationIsVisible="0",
    defaultConfigurationName="Release",
)
add(
    target_cfg_list,
    isa="XCConfigurationList",
    buildConfigurations=[target_debug, target_release],
    defaultConfigurationIsVisible="0",
    defaultConfigurationName="Release",
)

add(
    test_cfg_list,
    isa="XCConfigurationList",
    buildConfigurations=[test_debug, test_release],
    defaultConfigurationIsVisible="0",
    defaultConfigurationName="Release",
)

add(
    project_id,
    isa="PBXProject",
    attributes={
        "BuildIndependentTargetsInParallel": "1",
        "LastUpgradeCheck": "2700",
        "TargetAttributes": {
            target_id: {
                "CreatedOnToolsVersion": "27.2",
                "ProvisioningStyle": "Automatic",
            }
        },
    },
    buildConfigurationList=project_cfg_list,
    compatibilityVersion="Xcode 14.0",
    developmentRegion="zh-Hans",
    hasScannedForEncodings="0",
    knownRegions=["zh-Hans", "en", "Base"],
    mainGroup=main_group,
    productRefGroup=products_group,
    projectDirPath="",
    projectRoot="",
    targets=[target_id, test_target_id],
)

project = {
    "archiveVersion": "1",
    "classes": {},
    "objectVersion": "56",
    "objects": objects,
    "rootObject": project_id,
}

def pbxproj_quote(value):
    if re.fullmatch(r"[A-Za-z0-9_./$(){}@-]+", value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def pbxproj_serialize(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, dict):
        lines = ["{"]
        for key, val in value.items():
            lines.append(f"{pad}\t{pbxproj_quote(key)} = {pbxproj_serialize(val, indent + 1)};")
        lines.append(f"{pad}}}")
        return "\n".join(lines)
    if isinstance(value, list):
        lines = ["("]
        for val in value:
            lines.append(f"{pad}\t{pbxproj_serialize(val, indent + 1)},")
        lines.append(f"{pad})")
        return "\n".join(lines)
    return pbxproj_quote(str(value))


PROJECT_DIR.mkdir(parents=True, exist_ok=True)
WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)
(PROJECT_DIR / "project.pbxproj").write_text(
    "// !$*UTF8*$!\n" + pbxproj_serialize(project) + "\n",
    encoding="utf-8",
)
(WORKSPACE_DIR / "contents.xcworkspacedata").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<Workspace version = "1.0">\n'
    '   <FileRef location = "self:">\n'
    '   </FileRef>\n'
    '</Workspace>\n',
    encoding="utf-8",
)

SCHEMES_DIR = PROJECT_DIR / "xcshareddata" / "xcschemes"
SCHEMES_DIR.mkdir(parents=True, exist_ok=True)
test_reference = (
    f'<BuildableReference BuildableIdentifier="primary" '
    f'BlueprintIdentifier="{test_target_id}" '
    f'BuildableName="ShortsLibraryTests.xctest" '
    f'BlueprintName="ShortsLibraryTests" '
    f'ReferencedContainer="container:ShortsLibrary.xcodeproj">'
    f'</BuildableReference>'
)
scheme_text = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">
            {test_reference}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
         <TestableReference skipped="NO">
            {test_reference}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"></ArchiveAction>
</Scheme>
'''
(SCHEMES_DIR / "ShortsLibraryTests.xcscheme").write_text(scheme_text, encoding="utf-8")

print(f"Generated {PROJECT_DIR} with {len(swift_files)} Swift files")
