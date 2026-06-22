#!/usr/bin/env python3
"""Generate LocalTranscriber.xcodeproj/project.pbxproj"""

import os
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARKETING_VERSION = "0.1.5"

APP_SOURCES = [
    "LocalTranscriber/LocalTranscriberApp.swift",
    "LocalTranscriber/Domain/TranscriptionJob.swift",
    "LocalTranscriber/Domain/Transcript.swift",
    "LocalTranscriber/Domain/TranscriptSegment.swift",
    "LocalTranscriber/Domain/AppSettings.swift",
    "LocalTranscriber/Domain/ExportFormat.swift",
    "LocalTranscriber/Domain/TranscriptionProgressUpdate.swift",
    "LocalTranscriber/Domain/TranscriptionProgressDisplay.swift",
    "LocalTranscriber/Domain/TranscriptTextSanitizer.swift",
    "LocalTranscriber/Domain/TranscriptPartialTextBuilder.swift",
    "LocalTranscriber/Infrastructure/AppDirectories.swift",
    "LocalTranscriber/Infrastructure/Logger.swift",
    "LocalTranscriber/Infrastructure/ErrorMapper.swift",
    "LocalTranscriber/Infrastructure/AppVersion.swift",
    "LocalTranscriber/Infrastructure/SupportedAudioTypes.swift",
    "LocalTranscriber/Services/Transcriber.swift",
    "LocalTranscriber/Services/WhisperKitTranscriber.swift",
    "LocalTranscriber/Services/ModelAvailabilityService.swift",
    "LocalTranscriber/Services/ModelDownloadService.swift",
    "LocalTranscriber/Services/AudioImportService.swift",
    "LocalTranscriber/Services/AudioFileService.swift",
    "LocalTranscriber/Services/DropFileNameResolver.swift",
    "LocalTranscriber/Services/DropURLParser.swift",
    "LocalTranscriber/Services/DropImportService.swift",
    "LocalTranscriber/Services/AudioFileNameResolver.swift",
    "LocalTranscriber/Services/ExportService.swift",
    "LocalTranscriber/Services/AudioPlayerService.swift",
    "LocalTranscriber/Services/SecurityScopedFileAccess.swift",
    "LocalTranscriber/Services/UpdateCheckService.swift",
    "LocalTranscriber/Presentation/MainWindowView.swift",
    "LocalTranscriber/Presentation/MainWindowViewModel.swift",
    "LocalTranscriber/Presentation/UpdateCheckViewModel.swift",
    "LocalTranscriber/Presentation/StatusBarView.swift",
    "LocalTranscriber/Presentation/FileDropView.swift",
    "LocalTranscriber/Presentation/TranscriptEditorView.swift",
]

TEST_SOURCES = [
    "LocalTranscriberTests/ExportServiceTests.swift",
    "LocalTranscriberTests/TranscriptModelTests.swift",
    "LocalTranscriberTests/TranscriptionSmokeTests.swift",
    "LocalTranscriberTests/ModelAvailabilityServiceTests.swift",
    "LocalTranscriberTests/TranscriptionProgressDisplayTests.swift",
    "LocalTranscriberTests/ModelDownloadIntegrationTests.swift",
    "LocalTranscriberTests/ModelAvailabilityPathTests.swift",
    "LocalTranscriberTests/ModelDownloadServiceTests.swift",
    "LocalTranscriberTests/WhisperKitTranscriberTests.swift",
    "LocalTranscriberTests/AudioImportServiceTests.swift",
    "LocalTranscriberTests/AudioFileServiceTests.swift",
    "LocalTranscriberTests/MainWindowViewModelImportTests.swift",
    "LocalTranscriberTests/MainWindowViewModelProgressTests.swift",
    "LocalTranscriberTests/TranscriptTextSanitizerTests.swift",
    "LocalTranscriberTests/TranscriptPartialTextBuilderTests.swift",
    "LocalTranscriberTests/AudioPlayerServiceTests.swift",
    "LocalTranscriberTests/AppVersionTests.swift",
    "LocalTranscriberTests/UpdateCheckServiceTests.swift",
]

RESOURCES = [
    "Config/Defaults.plist",
    "LocalTranscriber/Assets.xcassets",
]

EXTRA_FILES = [
    "LocalTranscriber/LocalTranscriber.entitlements",
    "LocalTranscriber/Info.plist",
]


def uid():
    return uuid.uuid4().hex[:24].upper()


def pbx_file_ref(path):
    basename = os.path.basename(path)
    if path.endswith(".swift"):
        return f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {basename}; sourceTree = \"<group>\"; }}"
    if path.endswith(".plist") and "Defaults" in path:
        return f"{{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {basename}; sourceTree = \"<group>\"; }}"
    if path.endswith(".entitlements"):
        return f"{{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = {basename}; sourceTree = \"<group>\"; }}"
    if path.endswith("Info.plist"):
        return f"{{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {basename}; sourceTree = \"<group>\"; }}"
    if path.endswith(".xcassets"):
        return f"{{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {basename}; sourceTree = \"<group>\"; }}"
    raise ValueError(path)


ids = {
    "project": uid(),
    "main_group": uid(),
    "products_group": uid(),
    "config_group": uid(),
    "app_target": uid(),
    "test_target": uid(),
    "app_product": uid(),
    "test_product": uid(),
    "sources_phase_app": uid(),
    "resources_phase_app": uid(),
    "frameworks_phase_app": uid(),
    "sources_phase_test": uid(),
    "frameworks_phase_test": uid(),
    "test_dep": uid(),
    "app_proxy": uid(),
    "whisperkit_ref": uid(),
    "whisperkit_product": uid(),
    "pkg_ref": uid(),
    "debug_config": uid(),
    "release_config": uid(),
    "app_debug": uid(),
    "app_release": uid(),
    "test_debug": uid(),
    "test_release": uid(),
    "project_config_list": uid(),
    "app_config_list": uid(),
    "test_config_list": uid(),
    "domain_group": uid(),
    "infra_group": uid(),
    "services_group": uid(),
    "presentation_group": uid(),
    "local_group": uid(),
    "tests_group": uid(),
}

file_refs = {}
build_files = {}

all_paths = APP_SOURCES + TEST_SOURCES + RESOURCES + EXTRA_FILES
for path in all_paths:
    file_refs[path] = uid()

for path in APP_SOURCES + TEST_SOURCES:
    build_files[path] = uid()

for path in RESOURCES:
    build_files[path] = uid()

lines = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("	archiveVersion = 1;")
lines.append("	classes = {};")
lines.append("	objectVersion = 56;")
lines.append("	objects = {")

for path, bf in build_files.items():
    fr = file_refs[path]
    basename = os.path.basename(path)
    if path.endswith(".swift"):
        lines.append(f"		{bf} /* {basename} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {basename} */; }};")
    else:
        lines.append(f"		{bf} /* {basename} in Resources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {basename} */; }};")

lines.append(
    f"		{ids['whisperkit_product']} /* WhisperKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids['whisperkit_ref']} /* WhisperKit */; }};"
)

lines.append(
    f"		{ids['app_product']} /* Transnote.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Transnote.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
lines.append(
    f"		{ids['test_product']} /* LocalTranscriberTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LocalTranscriberTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
)

for path, fr in file_refs.items():
    basename = os.path.basename(path)
    lines.append(f"		{fr} /* {basename} */ = {pbx_file_ref(path)};")

lines.append(f"		{ids['frameworks_phase_app']} /* Frameworks */ = {{")
lines.append("			isa = PBXFrameworksBuildPhase;")
lines.append("			buildActionMask = 2147483647;")
lines.append("			files = (")
lines.append(f"				{ids['whisperkit_product']} /* WhisperKit in Frameworks */,")
lines.append("			);")
lines.append("			runOnlyForDeploymentPostprocessing = 0;")
lines.append("		};")

lines.append(f"		{ids['frameworks_phase_test']} /* Frameworks */ = {{")
lines.append("			isa = PBXFrameworksBuildPhase;")
lines.append("			buildActionMask = 2147483647;")
lines.append("			files = ();")
lines.append("			runOnlyForDeploymentPostprocessing = 0;")
lines.append("		};")

def group(gid, name, child_refs, path=None):
    lines.append(f"		{gid} /* {name} */ = {{")
    lines.append("			isa = PBXGroup;")
    lines.append("			children = (")
    for cref in child_refs:
        lines.append(f"				{cref},")
    lines.append("			);")
    if path:
        lines.append(f"			path = {path};")
    lines.append("			sourceTree = \"<group>\";")
    lines.append("		};")

domain_children = [f"{file_refs[p]} /* {os.path.basename(p)} */" for p in APP_SOURCES if "/Domain/" in p]
infra_children = [f"{file_refs[p]} /* {os.path.basename(p)} */" for p in APP_SOURCES if "/Infrastructure/" in p]
services_children = [f"{file_refs[p]} /* {os.path.basename(p)} */" for p in APP_SOURCES if "/Services/" in p]
presentation_children = [f"{file_refs[p]} /* {os.path.basename(p)} */" for p in APP_SOURCES if "/Presentation/" in p]

group(ids["domain_group"], "Domain", domain_children, "Domain")
group(ids["infra_group"], "Infrastructure", infra_children, "Infrastructure")
group(ids["services_group"], "Services", services_children, "Services")
group(ids["presentation_group"], "Presentation", presentation_children, "Presentation")

local_children = [
    f"{file_refs['LocalTranscriber/LocalTranscriberApp.swift']} /* LocalTranscriberApp.swift */",
    f"{ids['domain_group']} /* Domain */",
    f"{ids['infra_group']} /* Infrastructure */",
    f"{ids['services_group']} /* Services */",
    f"{ids['presentation_group']} /* Presentation */",
    f"{file_refs['LocalTranscriber/Assets.xcassets']} /* Assets.xcassets */",
    f"{file_refs['LocalTranscriber/Info.plist']} /* Info.plist */",
    f"{file_refs['LocalTranscriber/LocalTranscriber.entitlements']} /* LocalTranscriber.entitlements */",
]
group(ids["local_group"], "LocalTranscriber", local_children, "LocalTranscriber")

tests_children = [f"{file_refs[p]} /* {os.path.basename(p)} */" for p in TEST_SOURCES]
group(ids["tests_group"], "LocalTranscriberTests", tests_children, "LocalTranscriberTests")

config_children = [f"{file_refs['Config/Defaults.plist']} /* Defaults.plist */"]
group(ids["config_group"], "Config", config_children, "Config")

products_children = [
    f"{ids['app_product']} /* Transnote.app */",
    f"{ids['test_product']} /* LocalTranscriberTests.xctest */",
]
group(ids["products_group"], "Products", products_children)

main_children = [
    f"{ids['local_group']} /* LocalTranscriber */",
    f"{ids['tests_group']} /* LocalTranscriberTests */",
    f"{ids['config_group']} /* Config */",
    f"{ids['products_group']} /* Products */",
]
group(ids["main_group"], "Main", main_children)

lines.append(f"		{ids['app_proxy']} /* PBXContainerItemProxy */ = {{")
lines.append("			isa = PBXContainerItemProxy;")
lines.append(f"			containerPortal = {ids['project']} /* Project object */;")
lines.append("			proxyType = 1;")
lines.append(f"			remoteGlobalIDString = {ids['app_target']};")
lines.append("			remoteInfo = LocalTranscriber;")
lines.append("		};")

lines.append(f"		{ids['test_dep']} /* PBXTargetDependency */ = {{")
lines.append("			isa = PBXTargetDependency;")
lines.append(f"			target = {ids['app_target']} /* LocalTranscriber */;")
lines.append(f"			targetProxy = {ids['app_proxy']} /* PBXContainerItemProxy */;")
lines.append("		};")

lines.append(f"		{ids['app_target']} /* LocalTranscriber */ = {{")
lines.append("			isa = PBXNativeTarget;")
lines.append(f"			buildConfigurationList = {ids['app_config_list']} /* Build configuration list for PBXNativeTarget \"LocalTranscriber\" */;")
lines.append("			buildPhases = (")
lines.append(f"				{ids['sources_phase_app']} /* Sources */,")
lines.append(f"				{ids['frameworks_phase_app']} /* Frameworks */,")
lines.append(f"				{ids['resources_phase_app']} /* Resources */,")
lines.append("			);")
lines.append("			buildRules = ();")
lines.append("			dependencies = ();")
lines.append("			name = LocalTranscriber;")
lines.append("			packageProductDependencies = (")
lines.append(f"				{ids['whisperkit_ref']} /* WhisperKit */,")
lines.append("			);")
lines.append("			productName = LocalTranscriber;")
lines.append(f"			productReference = {ids['app_product']} /* Transnote.app */;")
lines.append("			productType = \"com.apple.product-type.application\";")
lines.append("		};")

lines.append(f"		{ids['test_target']} /* LocalTranscriberTests */ = {{")
lines.append("			isa = PBXNativeTarget;")
lines.append(f"			buildConfigurationList = {ids['test_config_list']} /* Build configuration list for PBXNativeTarget \"LocalTranscriberTests\" */;")
lines.append("			buildPhases = (")
lines.append(f"				{ids['sources_phase_test']} /* Sources */,")
lines.append(f"				{ids['frameworks_phase_test']} /* Frameworks */,")
lines.append("			);")
lines.append("			buildRules = ();")
lines.append("			dependencies = (")
lines.append(f"				{ids['test_dep']} /* PBXTargetDependency */,")
lines.append("			);")
lines.append("			name = LocalTranscriberTests;")
lines.append("			productName = LocalTranscriberTests;")
lines.append(f"			productReference = {ids['test_product']} /* LocalTranscriberTests.xctest */;")
lines.append("			productType = \"com.apple.product-type.bundle.unit-test\";")
lines.append("		};")

lines.append(f"		{ids['project']} /* Project object */ = {{")
lines.append("			isa = PBXProject;")
lines.append("			attributes = {")
lines.append("				BuildIndependentTargetsInParallel = 1;")
lines.append("				LastSwiftUpdateCheck = 1600;")
lines.append("				LastUpgradeCheck = 1600;")
lines.append("				TargetAttributes = {")
lines.append(f"					{ids['app_target']} = {{")
lines.append("						CreatedOnToolsVersion = 16.0;")
lines.append("					};")
lines.append(f"					{ids['test_target']} = {{")
lines.append("						CreatedOnToolsVersion = 16.0;")
lines.append(f"						TestTargetID = {ids['app_target']};")
lines.append("					};")
lines.append("				};")
lines.append("			};")
lines.append(f"			buildConfigurationList = {ids['project_config_list']} /* Build configuration list for PBXProject \"LocalTranscriber\" */;")
lines.append("			compatibilityVersion = \"Xcode 14.0\";")
lines.append("			developmentRegion = en;")
lines.append("			hasScannedForEncodings = 0;")
lines.append("			knownRegions = (en, Base);")
lines.append(f"			mainGroup = {ids['main_group']};")
lines.append("			packageReferences = (")
lines.append(f"				{ids['pkg_ref']} /* XCRemoteSwiftPackageReference argmax-oss-swift */,")
lines.append("			);")
lines.append(f"			productRefGroup = {ids['products_group']} /* Products */;")
lines.append("			projectDirPath = \"\";")
lines.append("			projectRoot = \"\";")
lines.append("			targets = (")
lines.append(f"				{ids['app_target']} /* LocalTranscriber */,")
lines.append(f"				{ids['test_target']} /* LocalTranscriberTests */,")
lines.append("			);")
lines.append("		};")

lines.append(f"		{ids['sources_phase_app']} /* Sources */ = {{")
lines.append("			isa = PBXSourcesBuildPhase;")
lines.append("			buildActionMask = 2147483647;")
lines.append("			files = (")
for p in APP_SOURCES:
    bf = build_files[p]
    basename = os.path.basename(p)
    lines.append(f"				{bf} /* {basename} in Sources */,")
lines.append("			);")
lines.append("			runOnlyForDeploymentPostprocessing = 0;")
lines.append("		};")

lines.append(f"		{ids['sources_phase_test']} /* Sources */ = {{")
lines.append("			isa = PBXSourcesBuildPhase;")
lines.append("			buildActionMask = 2147483647;")
lines.append("			files = (")
for p in TEST_SOURCES:
    bf = build_files[p]
    basename = os.path.basename(p)
    lines.append(f"				{bf} /* {basename} in Sources */,")
lines.append("			);")
lines.append("			runOnlyForDeploymentPostprocessing = 0;")
lines.append("		};")

lines.append(f"		{ids['resources_phase_app']} /* Resources */ = {{")
lines.append("			isa = PBXResourcesBuildPhase;")
lines.append("			buildActionMask = 2147483647;")
lines.append("			files = (")
for p in RESOURCES:
    bf = build_files[p]
    basename = os.path.basename(p)
    lines.append(f"				{bf} /* {basename} in Resources */,")
lines.append("			);")
lines.append("			runOnlyForDeploymentPostprocessing = 0;")
lines.append("		};")

def build_settings(name, cfg_id, is_app=True, is_test=False):
    lines.append(f"		{cfg_id} /* {name} */ = {{")
    lines.append("			isa = XCBuildConfiguration;")
    lines.append("			buildSettings = {")
    if is_app and not is_test:
        lines.append("				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
        lines.append("				CODE_SIGN_ENTITLEMENTS = LocalTranscriber/LocalTranscriber.entitlements;")
        lines.append("				CODE_SIGN_STYLE = Automatic;")
        lines.append("				COMBINE_HIDPI_IMAGES = YES;")
        lines.append("				CURRENT_PROJECT_VERSION = 1;")
        lines.append("				DEVELOPMENT_TEAM = \"\";")
        lines.append("				ENABLE_HARDENED_RUNTIME = YES;")
        if name == "Debug":
            lines.append("				ENABLE_TESTABILITY = YES;")
        lines.append("				GENERATE_INFOPLIST_FILE = NO;")
        lines.append("				INFOPLIST_FILE = LocalTranscriber/Info.plist;")
        lines.append("				LD_RUNPATH_SEARCH_PATHS = (")
        lines.append("					\"$(inherited)\",")
        lines.append("					\"@executable_path/../Frameworks\",")
        lines.append("				);")
        lines.append("				MACOSX_DEPLOYMENT_TARGET = 14.0;")
        lines.append(f"				MARKETING_VERSION = {MARKETING_VERSION};")
        lines.append("				PRODUCT_BUNDLE_IDENTIFIER = com.transnote.LocalTranscriber;")
        lines.append("				PRODUCT_MODULE_NAME = LocalTranscriber;")
        lines.append("				PRODUCT_NAME = Transnote;")
        lines.append("				SWIFT_EMIT_LOC_STRINGS = YES;")
        lines.append("				SWIFT_VERSION = 5.0;")
    elif is_test:
        lines.append("				BUNDLE_LOADER = \"$(TEST_HOST)\";")
        lines.append("				CODE_SIGN_STYLE = Automatic;")
        lines.append("				CURRENT_PROJECT_VERSION = 1;")
        lines.append("				DEVELOPMENT_TEAM = \"\";")
        lines.append("				GENERATE_INFOPLIST_FILE = YES;")
        lines.append("				MACOSX_DEPLOYMENT_TARGET = 14.0;")
        lines.append(f"				MARKETING_VERSION = {MARKETING_VERSION};")
        lines.append("				PRODUCT_BUNDLE_IDENTIFIER = com.transnote.LocalTranscriberTests;")
        lines.append("				PRODUCT_NAME = \"$(TARGET_NAME)\";")
        lines.append("				SWIFT_EMIT_LOC_STRINGS = NO;")
        lines.append("				SWIFT_VERSION = 5.0;")
        lines.append("				TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/Transnote.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Transnote\";")
    else:
        lines.append("				ALWAYS_SEARCH_USER_PATHS = NO;")
        lines.append("				CLANG_ENABLE_MODULES = YES;")
        lines.append("				CLANG_ENABLE_OBJC_ARC = YES;")
        if name == "Release":
            lines.append("				COPY_PHASE_STRIP = YES;")
            lines.append("				DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
            lines.append("				ENABLE_NS_ASSERTIONS = NO;")
        else:
            lines.append("				COPY_PHASE_STRIP = NO;")
            lines.append("				DEBUG_INFORMATION_FORMAT = dwarf;")
        lines.append("				ENABLE_STRICT_OBJC_MSGSEND = YES;")
        lines.append("				GCC_C_LANGUAGE_STANDARD = gnu17;")
        lines.append("				MACOSX_DEPLOYMENT_TARGET = 14.0;")
        if name == "Release":
            lines.append("				ONLY_ACTIVE_ARCH = NO;")
        else:
            lines.append("				ONLY_ACTIVE_ARCH = YES;")
        lines.append("				SDKROOT = macosx;")
        if name == "Release":
            lines.append("				SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"$(inherited)\";")
            lines.append("				SWIFT_OPTIMIZATION_LEVEL = \"-O\";")
        else:
            lines.append("				SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";")
            lines.append("				SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    if name == "Debug" and not is_app:
        lines.append("				GCC_DYNAMIC_NO_PIC = NO;")
        lines.append("				GCC_OPTIMIZATION_LEVEL = 0;")
    if name == "Release" and not is_app:
        lines.append("				SWIFT_COMPILATION_MODE = wholemodule;")
        lines.append("				VALIDATE_PRODUCT = YES;")
    lines.append("			};")
    lines.append("			name = " + name + ";")
    lines.append("		};")

build_settings("Debug", ids["debug_config"], is_app=False)
build_settings("Release", ids["release_config"], is_app=False)
build_settings("Debug", ids["app_debug"], is_app=True)
build_settings("Release", ids["app_release"], is_app=True)
build_settings("Debug", ids["test_debug"], is_app=True, is_test=True)
build_settings("Release", ids["test_release"], is_app=True, is_test=True)

lines.append(f"		{ids['project_config_list']} /* Build configuration list for PBXProject \"LocalTranscriber\" */ = {{")
lines.append("			isa = XCConfigurationList;")
lines.append("			buildConfigurations = (")
lines.append(f"				{ids['debug_config']} /* Debug */,")
lines.append(f"				{ids['release_config']} /* Release */,")
lines.append("			);")
lines.append("			defaultConfigurationIsVisible = 0;")
lines.append("			defaultConfigurationName = Release;")
lines.append("		};")

lines.append(f"		{ids['app_config_list']} /* Build configuration list for PBXNativeTarget \"LocalTranscriber\" */ = {{")
lines.append("			isa = XCConfigurationList;")
lines.append("			buildConfigurations = (")
lines.append(f"				{ids['app_debug']} /* Debug */,")
lines.append(f"				{ids['app_release']} /* Release */,")
lines.append("			);")
lines.append("			defaultConfigurationIsVisible = 0;")
lines.append("			defaultConfigurationName = Release;")
lines.append("		};")

lines.append(f"		{ids['test_config_list']} /* Build configuration list for PBXNativeTarget \"LocalTranscriberTests\" */ = {{")
lines.append("			isa = XCConfigurationList;")
lines.append("			buildConfigurations = (")
lines.append(f"				{ids['test_debug']} /* Debug */,")
lines.append(f"				{ids['test_release']} /* Release */,")
lines.append("			);")
lines.append("			defaultConfigurationIsVisible = 0;")
lines.append("			defaultConfigurationName = Release;")
lines.append("		};")

lines.append(f"		{ids['pkg_ref']} /* XCRemoteSwiftPackageReference argmax-oss-swift */ = {{")
lines.append("			isa = XCRemoteSwiftPackageReference;")
lines.append("			repositoryURL = \"https://github.com/argmaxinc/argmax-oss-swift\";")
lines.append("			requirement = {")
lines.append("				kind = upToNextMajorVersion;")
lines.append("				minimumVersion = 0.9.0;")
lines.append("			};")
lines.append("		};")

lines.append(f"		{ids['whisperkit_ref']} /* WhisperKit */ = {{")
lines.append("			isa = XCSwiftPackageProductDependency;")
lines.append(f"			package = {ids['pkg_ref']} /* XCRemoteSwiftPackageReference argmax-oss-swift */;")
lines.append("			productName = WhisperKit;")
lines.append("		};")

lines.append("	};")
lines.append(f"	rootObject = {ids['project']} /* Project object */;")
lines.append("}")

output_path = os.path.join(ROOT, "LocalTranscriber.xcodeproj", "project.pbxproj")
os.makedirs(os.path.dirname(output_path), exist_ok=True)
with open(output_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

# workspace
workspace_dir = os.path.join(ROOT, "LocalTranscriber.xcodeproj", "project.xcworkspace")
os.makedirs(workspace_dir, exist_ok=True)
with open(os.path.join(workspace_dir, "contents.xcworkspacedata"), "w") as f:
    f.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
    f.write("<Workspace version = \"1.0\">\n")
    f.write("   <FileRef location = \"self:\"></FileRef>\n")
    f.write("</Workspace>\n")

scheme_dir = os.path.join(ROOT, "LocalTranscriber.xcodeproj", "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ids['app_target']}" BuildableName="Transnote.app" BlueprintName="LocalTranscriber" ReferencedContainer="container:LocalTranscriber.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
         <TestableReference skipped="NO" testExecutionOrdering="random">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ids['test_target']}" BuildableName="LocalTranscriberTests.xctest" BlueprintName="LocalTranscriberTests" ReferencedContainer="container:LocalTranscriber.xcodeproj"/>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ids['app_target']}" BuildableName="Transnote.app" BlueprintName="LocalTranscriber" ReferencedContainer="container:LocalTranscriber.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="NO">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ids['app_target']}" BuildableName="Transnote.app" BlueprintName="LocalTranscriber" ReferencedContainer="container:LocalTranscriber.xcodeproj"/>
      </BuildableProductRunnable>
   </ArchiveAction>
</Scheme>
'''
with open(os.path.join(scheme_dir, "LocalTranscriber.xcscheme"), "w") as f:
    f.write(scheme)

print(f"Generated {output_path}")
