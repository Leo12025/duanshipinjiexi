#!/usr/bin/env python3
import hashlib
import json
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
asset_path = "ShortsLibrary/Assets.xcassets"
privacy_path = "ShortsLibrary/PrivacyInfo.xcprivacy"
info_path = "ShortsLibrary/Info.plist"
product_path = "ShortsLibrary.app"

objects: dict[str, dict] = {}


def add(object_id: str, **fields) -> None:
    objects[object_id] = fields


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

source_ids = []
resource_ids = []
group_children = []

for rel in swift_files:
    ref = ident("file:" + rel)
    build = ident("build:" + rel)
    name = Path(rel).name
    add(
        ref,
        isa="PBXFileReference",
        lastKnownFileType="sourcecode.swift",
        path=rel,
        sourceTree="SOURCE_ROOT",
    )
    add(build, isa="PBXBuildFile", fileRef=ref)
    source_ids.append(build)
    group_children.append(ref)

asset_ref = ident("file:" + asset_path)
asset_build = ident("build:" + asset_path)
add(
    asset_ref,
    isa="PBXFileReference",
    lastKnownFileType="folder.assetcatalog",
    path=asset_path,
    sourceTree="SOURCE_ROOT",
)
add(asset_build, isa="PBXBuildFile", fileRef=asset_ref)
resource_ids.append(asset_build)
group_children.append(asset_ref)

privacy_ref = ident("file:" + privacy_path)
privacy_build = ident("build:" + privacy_path)
add(
    privacy_ref,
    isa="PBXFileReference",
    lastKnownFileType="text.plist.xml",
    path=privacy_path,
    sourceTree="SOURCE_ROOT",
)
add(privacy_build, isa="PBXBuildFile", fileRef=privacy_ref)
resource_ids.append(privacy_build)
group_children.append(privacy_ref)

info_ref = ident("file:" + info_path)
add(
    info_ref,
    isa="PBXFileReference",
    lastKnownFileType="text.plist.xml",
    path=info_path,
    sourceTree="SOURCE_ROOT",
)
group_children.append(info_ref)

add(
    product_ref,
    isa="PBXFileReference",
    explicitFileType="wrapper.application",
    includeInIndex="0",
    path=product_path,
    sourceTree="BUILT_PRODUCTS_DIR",
)

add(
    main_group,
    isa="PBXGroup",
    children=[sources_group, products_group],
    sourceTree="<group>",
)
add(
    sources_group,
    isa="PBXGroup",
    children=group_children,
    name="Sources",
    sourceTree="<group>",
)
add(
    products_group,
    isa="PBXGroup",
    children=[product_ref],
    name="Products",
    sourceTree="<group>",
)

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

for config_id, name, settings in [
    (project_debug, "Debug", debug_settings),
    (project_release, "Release", release_settings),
    (target_debug, "Debug", debug_settings),
    (target_release, "Release", release_settings),
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
    developmentRegion="en",
    hasScannedForEncodings="0",
    knownRegions=["en", "Base"],
    mainGroup=main_group,
    productRefGroup=products_group,
    projectDirPath="",
    projectRoot="",
    targets=[target_id],
)

project = {
    "archiveVersion": "1",
    "classes": {},
    "objectVersion": "56",
    "objects": objects,
    "rootObject": project_id,
}

PROJECT_DIR.mkdir(parents=True, exist_ok=True)
WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)
(PROJECT_DIR / "project.pbxproj").write_text(
    json.dumps(project, indent=2, ensure_ascii=False) + "\n",
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

print(f"Generated {PROJECT_DIR} with {len(swift_files)} Swift files")
