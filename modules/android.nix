{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      system,
      lib,
      config,
      ...
    }:
    let
      baseRepoJson = pkgs.path + "/pkgs/development/mobile/androidenv/repo.json";
      automotiveOverlayJson = ../android-automotive-images.json;
      emulatorOverlayJson = ../android-emulator-overlay.json;
      mergedRepoJson =
        let
          baseRepo = builtins.fromJSON (builtins.readFile baseRepoJson);
          automotiveOverlay =
            if builtins.pathExists automotiveOverlayJson then
              builtins.fromJSON (builtins.readFile automotiveOverlayJson)
            else
              { };
          emulatorOverlay =
            if builtins.pathExists emulatorOverlayJson then
              builtins.fromJSON (builtins.readFile emulatorOverlayJson)
            else
              { };
        in
        pkgs.writeText "androidenv-repo.json" (
          builtins.toJSON (lib.recursiveUpdate (lib.recursiveUpdate baseRepo automotiveOverlay) emulatorOverlay)
        );
      defaultRepoJson = mergedRepoJson;

      defaultAbiVersion =
        if pkgs.stdenv.hostPlatform.isAarch64 then "arm64-v8a" else "x86_64";

      sanitizeName = value: lib.replaceStrings [ "." "_" ] [ "-" "-" ] value;

      mkAndroidEnvironment =
        {
          platformVersions ? [
            "35"
            "36"
            "latest"
          ],
          emulatorPlatformVersion ? "latest",
          buildToolsVersion ? "latest",
          extraBuildToolsVersions ? [
            "35.0.0"
            "36.0.0"
          ],
          cmdLineToolsVersion ? "latest",
          includeEmulator ? true,
          emulatorVersion ? "latest",
          includeNdk ? false,
          ndkVersion ? "latest",
          includeSources ? true,
          ide ? "android-studio",
          extraPackages ? [ ],
          includeExtras ? [ ],
          repoJson ? defaultRepoJson,
          repoXmls ? null,
          abiVersion ? defaultAbiVersion,
          systemImageType ? null,
          preferredSystemImageTypes ? [
            "google_apis_playstore"
            "google_apis"
            "default"
            "page_size_16kb"
            "android-tv"
            "android-wear"
            "android-automotive"
            "android-automotive-playstore"
          ],
          androidUserHome ? "$PWD/.android",
          androidAvdHome ? "$PWD/.android/avd",
          androidAvdFlags ? null,
          androidEmulatorFlags ? "-gpu swiftshader_indirect -no-snapshot",
          configOptions ? {
            "hw.keyboard" = "yes";
          },
        }:
        let
          repo = builtins.fromJSON (builtins.readFile repoJson);
          repoOs =
            {
              x86_64-linux = "linux";
              x86_64-darwin = "macosx";
              aarch64-linux = "linux";
              aarch64-darwin = "macosx";
            }
            .${pkgs.stdenv.hostPlatform.system} or "all";
          repoArch =
            {
              x86_64-linux = "x64";
              x86_64-darwin = "x64";
              aarch64-linux = "aarch64";
              aarch64-darwin = "aarch64";
            }
            .${pkgs.stdenv.hostPlatform.system} or "all";

          resolveRepoVersion = key: version: if version == "latest" then repo.latest.${key} else toString version;

          resolvedCmdLineToolsVersion = resolveRepoVersion "cmdline-tools" cmdLineToolsVersion;
          resolvedEmulatorPlatformVersion = resolveRepoVersion "platforms" emulatorPlatformVersion;
          resolvedEmulatorVersion = resolveRepoVersion "emulator" emulatorVersion;
          resolvedPlatformVersions = lib.unique (
            map (resolveRepoVersion "platforms") ([ resolvedEmulatorPlatformVersion ] ++ platformVersions)
          );
          resolvedBuildToolsVersions = lib.unique (
            map (resolveRepoVersion "build-tools") ([ buildToolsVersion ] ++ extraBuildToolsVersions)
          );
          resolvedNdkVersion = resolveRepoVersion "ndk" ndkVersion;
          sourcePlatformsAvailable = builtins.attrNames (repo.packages.sources or { });
          missingSourcePlatforms = builtins.filter (platformVersion: !(builtins.elem platformVersion sourcePlatformsAvailable)) resolvedPlatformVersions;
          effectiveIncludeSources = includeSources && missingSourcePlatforms == [ ];

          availableImageTypes =
            if builtins.hasAttr resolvedEmulatorPlatformVersion repo.images then
              builtins.attrNames repo.images.${resolvedEmulatorPlatformVersion}
            else
              [ ];

          imageAbisFor =
            imageType:
            let
              imageNode = lib.attrByPath [ resolvedEmulatorPlatformVersion imageType ] null repo.images;
            in
            if imageNode == null then [ ] else builtins.attrNames imageNode;

          selectedSystemImageType =
            if systemImageType != null then
              systemImageType
            else
              lib.findFirst (
                imageType: lib.hasAttrByPath [ resolvedEmulatorPlatformVersion imageType abiVersion ] repo.images
              ) null preferredSystemImageTypes;

          selectedSystemImage =
            lib.attrByPath [ resolvedEmulatorPlatformVersion selectedSystemImageType abiVersion ] null repo.images;

          selectedSystemImagePackagePath =
            if selectedSystemImageType == null then
              throw ''
                No Android system image was found for platform ${resolvedEmulatorPlatformVersion} and ABI ${abiVersion}.
                Available image types: ${lib.concatStringsSep ", " availableImageTypes}
              ''
            else if !(lib.hasAttrByPath [ resolvedEmulatorPlatformVersion selectedSystemImageType abiVersion ] repo.images) then
              throw ''
                Android system image ${selectedSystemImageType}/${abiVersion} is not available for platform ${resolvedEmulatorPlatformVersion}.
                Available ABIs for ${selectedSystemImageType}: ${lib.concatStringsSep ", " (imageAbisFor selectedSystemImageType)}
              ''
            else if selectedSystemImage != null && selectedSystemImage ? path then
              lib.replaceStrings [ "/" ] [ ";" ] selectedSystemImage.path
            else
              "system-images;android-${resolvedEmulatorPlatformVersion};${selectedSystemImageType};${abiVersion}";

          customEmulatorVersions = [
            "36.5.10"
            "36.6.3"
          ];
          useCustomEmulator = includeEmulator && builtins.elem resolvedEmulatorVersion customEmulatorVersions;

          sdkArgs = {
            inherit
              cmdLineToolsVersion
              includeExtras
              repoJson
              repoXmls
              ;

            platformVersions = resolvedPlatformVersions;
            buildToolsVersions = resolvedBuildToolsVersions;
            ndkVersion = resolvedNdkVersion;
            abiVersions = [ abiVersion ];

            includeSystemImages = true;
            systemImageTypes = [ selectedSystemImageType ];
            includeSources = effectiveIncludeSources;

            includeEmulator =
              if useCustomEmulator then false else if includeEmulator then "if-supported" else false;
            emulatorVersion = emulatorVersion;
            includeNDK = if includeNdk then "if-supported" else false;

            extraLicenses = [
              "android-sdk-preview-license"
              "android-googletv-license"
              "android-sdk-arm-dbt-license"
              "google-gdk-license"
              "intel-android-extra-license"
              "intel-android-sysimage-license"
              "mips-android-sysimage-license"
            ];
          };

          androidComposition = pkgs.androidenv.composeAndroidPackages sdkArgs;
          platformTools = androidComposition.platform-tools;
          customEmulatorPackageInfo = lib.attrByPath [ "packages" "emulator" resolvedEmulatorVersion ] null repo;
          customEmulatorArchives =
            if customEmulatorPackageInfo == null then
              [ ]
            else
              builtins.filter (
                archive:
                let
                  isTargetOs = if builtins.hasAttr "os" archive then archive.os == repoOs || archive.os == "all" else true;
                  isTargetArch =
                    if builtins.hasAttr "arch" archive then archive.arch == repoArch || archive.arch == "all" else true;
                in
                isTargetOs && isTargetArch
              ) customEmulatorPackageInfo.archives;
          fetchedCustomEmulatorPackage =
            if !useCustomEmulator then
              null
            else if customEmulatorPackageInfo == null then
              throw "Android emulator ${resolvedEmulatorVersion} is missing from repo metadata."
            else if customEmulatorArchives == [ ] then
              throw "Android emulator ${resolvedEmulatorVersion} has no archive for ${repoOs}/${repoArch}."
            else
              customEmulatorPackageInfo
              // {
                archives = map (
                  archive:
                  pkgs.fetchurl {
                    name = builtins.baseNameOf archive.url;
                    url = archive.url;
                    sha1 = archive.sha1;
                  }
                ) customEmulatorArchives;
              };
          customEmulator =
            if !useCustomEmulator then
              null
            else
              (
                pkgs.callPackage (pkgs.path + "/pkgs/development/mobile/androidenv/emulator.nix") {
                  deployAndroidPackage = androidComposition.deployAndroidPackage;
                  package = fetchedCustomEmulatorPackage;
                  os = repoOs;
                  arch = repoArch;
                  postInstall = "";
                  meta = pkgs.androidenv.meta;
                }
              ).overrideAttrs
                (old: {
                  buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.libgbm ];
                  patchInstructions =
                    (old.patchInstructions or "")
                    + ''
                      addAutoPatchelfSearchPath ${pkgs.libgbm}/lib
                    '';
                });
          androidSdk = androidComposition.androidsdk;
          sdkDir = "${androidSdk}/libexec/android-sdk";
          jdk = pkgs.jetbrains.jdk;

          pkgsScrcpy = import inputs.nixpkgs-scrcpy {
            inherit system;
            config.allowUnfree = true;
          };

          idePackage =
            if ide == "android-studio" then
              [ pkgs.androidStudioPackages.stable ]
            else if ide == "intellij" then
              [ pkgs.jetbrains.idea ]
            else
              [ ];

          deviceName = "nix-avd-${sanitizeName resolvedEmulatorPlatformVersion}-${sanitizeName selectedSystemImageType}-${sanitizeName abiVersion}";

          emulatorRunner =
            if includeEmulator then
              pkgs.runCommandLocal "android-emulator-${sanitizeName resolvedEmulatorPlatformVersion}-${sanitizeName selectedSystemImageType}-${sanitizeName abiVersion}" {
                meta.mainProgram = "run-test-emulator";
              } ''
                mkdir -p "$out/bin"
                cat > "$out/bin/run-test-emulator" <<'EOF'
                #!${pkgs.runtimeShell} -e

                if [ "$TMPDIR" = "" ]; then
                    export TMPDIR=/tmp
                fi

                mkdir -p "${androidUserHome}"
                export ANDROID_USER_HOME="${androidUserHome}"

                mkdir -p "${androidAvdHome}"
                export ANDROID_AVD_HOME="${androidAvdHome}"
                export JAVA_HOME=${jdk.home}
                export PATH="$JAVA_HOME/bin:$PATH"

                ${lib.optionalString (customEmulator == null) ''
                  export ANDROID_SDK_ROOT=${sdkDir}
                ''}
                ${lib.optionalString (customEmulator != null) ''
                  runtimeSdkRoot="$(mktemp -d "$TMPDIR/nix-android-sdk-${deviceName}.XXXXXX")"
                  for sdkEntry in ${androidSdk}/libexec/android-sdk/*; do
                      sdkEntryBase="$(basename "$sdkEntry")"
                      case "$sdkEntryBase" in
                          cmdline-tools|emulator) ;;
                          *) ln -s "$sdkEntry" "$runtimeSdkRoot/$sdkEntryBase" ;;
                      esac
                  done
                  mkdir -p "$runtimeSdkRoot/cmdline-tools"
                  cp -r ${androidSdk}/libexec/android-sdk/cmdline-tools/${resolvedCmdLineToolsVersion} "$runtimeSdkRoot/cmdline-tools/"
                  cp -rs ${customEmulator}/libexec/android-sdk/emulator "$runtimeSdkRoot"/emulator
                  export ANDROID_SDK_ROOT="$runtimeSdkRoot"
                  cmdlineToolsBin="$ANDROID_SDK_ROOT/cmdline-tools/${resolvedCmdLineToolsVersion}/bin"
                ''}
                ${lib.optionalString (customEmulator == null) ''
                  cmdlineToolsBin="$ANDROID_SDK_ROOT/cmdline-tools/${resolvedCmdLineToolsVersion}/bin"
                ''}
                avdManagerBin="$cmdlineToolsBin/.avdmanager-wrapped"

                ${lib.optionalString (androidAvdFlags != null) ''
                  if [[ -z "$NIX_ANDROID_AVD_FLAGS" ]]; then
                      NIX_ANDROID_AVD_FLAGS="${androidAvdFlags}"
                  fi
                ''}

                ${lib.optionalString (androidEmulatorFlags != null) ''
                  if [[ -z "$NIX_ANDROID_EMULATOR_FLAGS" ]]; then
                      NIX_ANDROID_EMULATOR_FLAGS="${androidEmulatorFlags}"
                  fi
                ''}

                echo "Looking for a free TCP port in range 5554-5584" >&2
                for i in $(seq 5554 2 5584); do
                    if [ -z "$(${platformTools}/bin/adb devices | grep emulator-$i)" ]; then
                        port=$i
                        break
                    fi
                done

                if [ -z "$port" ]; then
                    echo "Unfortunately, the emulator port space is exhausted!" >&2
                    exit 1
                else
                    echo "We have a free TCP port: $port" >&2
                fi

                export ANDROID_SERIAL="emulator-$port"
                avdPath="$ANDROID_AVD_HOME/${deviceName}.avd"
                avdConfig="$avdPath/config.ini"

                if [ "$($avdManagerBin list avd | grep 'Name: ${deviceName}')" = "" ]; then
                    yes "" | $avdManagerBin create avd --force -n ${deviceName} -k "${selectedSystemImagePackagePath}" -p "$avdPath" $NIX_ANDROID_AVD_FLAGS

                    ${builtins.concatStringsSep "\n" (
                      lib.mapAttrsToList (configKey: configValue: ''
                        echo "${configKey} = ${configValue}" >> "$avdConfig"
                      '') configOptions
                    )}
                fi

                set_avd_config() {
                    local key="$1"
                    local value="$2"

                    if ${pkgs.gnugrep}/bin/grep -q "^''${key}[[:space:]]*=" "$avdConfig"; then
                        ${pkgs.gnused}/bin/sed -i "s|^''${key}[[:space:]]*=.*$|''${key} = ''${value}|" "$avdConfig"
                    else
                        echo "''${key} = ''${value}" >> "$avdConfig"
                    fi
                }

                if [[ -n "$NIX_ANDROID_SCREEN" ]]; then
                    if [[ ! "$NIX_ANDROID_SCREEN" =~ ^[0-9]+x[0-9]+$ ]]; then
                        echo "Invalid NIX_ANDROID_SCREEN value: $NIX_ANDROID_SCREEN (expected WIDTHxHEIGHT)" >&2
                        exit 1
                    fi

                    IFS=x read -r screen_width screen_height <<< "$NIX_ANDROID_SCREEN"
                    set_avd_config "hw.lcd.width" "$screen_width"
                    set_avd_config "hw.lcd.height" "$screen_height"
                    set_avd_config "skin.dynamic" "yes"
                    set_avd_config "skin.name" "$NIX_ANDROID_SCREEN"

                    case " $NIX_ANDROID_EMULATOR_FLAGS " in
                        *" -skin "*) ;;
                        *) NIX_ANDROID_EMULATOR_FLAGS="$NIX_ANDROID_EMULATOR_FLAGS -skin $NIX_ANDROID_SCREEN" ;;
                    esac
                fi

                if [[ -n "$NIX_ANDROID_DENSITY" ]]; then
                    if [[ ! "$NIX_ANDROID_DENSITY" =~ ^[0-9]+$ ]]; then
                        echo "Invalid NIX_ANDROID_DENSITY value: $NIX_ANDROID_DENSITY (expected integer DPI)" >&2
                        exit 1
                    fi

                    set_avd_config "hw.lcd.density" "$NIX_ANDROID_DENSITY"
                fi

                echo "\nLaunch the emulator"
                $ANDROID_SDK_ROOT/emulator/emulator -avd ${deviceName} -no-boot-anim -port $port $NIX_ANDROID_EMULATOR_FLAGS &

                echo "Waiting until the emulator has booted the ${deviceName} and the package manager is ready..." >&2
                ${platformTools}/bin/adb -s emulator-$port wait-for-device

                echo "Device state has been reached" >&2
                while [ -z "$(${platformTools}/bin/adb -s emulator-$port shell getprop dev.bootcomplete | grep 1)" ]; do
                    sleep 5
                done

                echo "dev.bootcomplete property is 1" >&2
                echo "ready" >&2
                EOF
                chmod +x "$out/bin/run-test-emulator"
              ''
            else
              null;

          androidImageCatalogJson = pkgs.writeText "android-image-catalog.json" (
            builtins.toJSON (
              lib.flatten (
                lib.mapAttrsToList (
                  platformVersion: imageTypes:
                  lib.flatten (
                    lib.mapAttrsToList (
                      imageType: abis:
                      lib.mapAttrsToList (
                        abi: image:
                        {
                          platform = platformVersion;
                          type = imageType;
                          abi = abi;
                          displayName = image.displayName or "${platformVersion}/${imageType}/${abi}";
                          path = image.path;
                          revision = image.revision;
                        }
                      ) abis
                    ) imageTypes
                  )
                ) repo.images
              )
            )
          );

          androidListImages = pkgs.writeShellApplication {
            name = "android-list-images";
            runtimeInputs = [ pkgs.jq ];
            text = ''
              jq -r '
                sort_by(.platform, .type, .abi)[] |
                "\(.platform)\t\(.type)\t\(.abi)\t\(.path)"
              ' ${androidImageCatalogJson}
            '';
          };

          localProp = ''
            mkdir -p "$ANDROID_USER_HOME" "$ANDROID_AVD_HOME"
            cat > local.properties <<EOF
            ## This file must *NOT* be checked into Version Control Systems,
            # as it contains information specific to your local configuration.
            #
            # Location of the SDK. This is only used by Gradle.
            sdk.dir=${sdkDir}
            EOF
          '';
        in
        rec {
          inherit
            abiVersion
            androidComposition
            androidImageCatalogJson
            androidListImages
            androidSdk
            deviceName
            emulatorRunner
            platformTools
            resolvedBuildToolsVersions
            resolvedEmulatorPlatformVersion
            missingSourcePlatforms
            selectedSystemImage
            selectedSystemImagePackagePath
            selectedSystemImageType
            sdkArgs
            sdkDir
            ;

          shell = pkgs.mkShell.override { stdenv = pkgs.gccStdenv; } {
            packages =
              [
                pkgs.cmake
                androidSdk
                platformTools
                pkgs.git-repo
                pkgsScrcpy.scrcpy
                androidListImages
              ]
              ++ lib.optional (customEmulator != null) customEmulator
              ++ lib.optional (emulatorRunner != null) emulatorRunner
              ++ idePackage
              ++ extraPackages;

            JAVA_HOME = jdk.home;

            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
              pkgs.fontconfig
              pkgs.cups
              pkgs.libxinerama
              pkgs.libxrandr
              pkgs.file
              pkgs.gtk3
              pkgs.glib
              pkgs.libGL
              pkgs.libx11
            ];

            shellHook = ''
              export QT_QPA_PLATFORM=${if pkgs.stdenv.isLinux then "xcb" else ""}
              export ANDROID_SDK_ROOT="${sdkDir}"
              export ANDROID_HOME="${sdkDir}"
              export ANDROID_USER_HOME="${androidUserHome}"
              export ANDROID_AVD_HOME="${androidAvdHome}"
              ${lib.optionalString (customEmulator != null) ''export PATH="${customEmulator}/bin:$PATH"''}
              ${lib.optionalString (customEmulator == null && includeEmulator) ''export PATH="${sdkDir}/emulator:$PATH"''}
              export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdkDir}/build-tools/${lib.head resolvedBuildToolsVersions}/aapt2"
              export DIRENV_LOG_FORMAT=""
              ${localProp}
              echo "Android SDK: ${sdkDir}"
              echo "Selected image: ${selectedSystemImagePackagePath}"
              echo "Resolution override: NIX_ANDROID_SCREEN=1280x720 NIX_ANDROID_DENSITY=213"
              ${lib.optionalString includeEmulator ''echo "Emulator binary: $(command -v emulator)"''}
              ${lib.optionalString (includeSources && !effectiveIncludeSources) ''echo "Sources disabled: no sources package for ${lib.concatStringsSep ", " missingSourcePlatforms}"''}
              ${lib.optionalString (emulatorRunner != null) ''echo "Run emulator: ${lib.getExe emulatorRunner}"''}
            '';
          };
        };

      defaultAndroid = mkAndroidEnvironment { ide = null; };
      automotiveAndroid = mkAndroidEnvironment {
        ide = null;
        platformVersions = [
          "33"
          "34x"
          "35x"
        ];
        emulatorPlatformVersion = "35x";
        preferredSystemImageTypes = [
          "android-automotive-playstore"
          "android-automotive"
        ];
      };
      automotive32Android = mkAndroidEnvironment {
        ide = null;
        platformVersions = [ "32" ];
        emulatorPlatformVersion = "32";
        repoJson = mergedRepoJson;
        emulatorVersion = "36.5.10";
        preferredSystemImageTypes = [ "android-automotive-playstore" ];
        androidEmulatorFlags = "-no-window -gpu swiftshader_indirect -no-audio -no-snapshot -accel on";
      };
      automotive33Android = mkAndroidEnvironment {
        ide = null;
        platformVersions = [ "33" ];
        emulatorPlatformVersion = "33";
        preferredSystemImageTypes = [ "android-automotive" ];
        androidEmulatorFlags = "-no-window -gpu swiftshader_indirect -no-snapshot -accel on";
      };
      automotive32CanaryAndroid = mkAndroidEnvironment {
        ide = null;
        platformVersions = [ "32" ];
        emulatorPlatformVersion = "32";
        repoJson = mergedRepoJson;
        emulatorVersion = "36.6.3";
        preferredSystemImageTypes = [ "android-automotive-playstore" ];
        androidEmulatorFlags = "-no-window -gpu swiftshader_indirect -no-audio -no-snapshot -accel on";
      };
    in
    {
      options.mkAndroidShell = lib.mkOption {
        type = lib.types.functionTo lib.types.package;
        default = args: (mkAndroidEnvironment args).shell;
        description = "Function to create a configured Android dev shell.";
      };

      config = {
        packages = {
          android-sdk = defaultAndroid.androidSdk;
          android-emulator = defaultAndroid.emulatorRunner;
          android-image-catalog = defaultAndroid.androidImageCatalogJson;
          android-list-images = defaultAndroid.androidListImages;
          android-automotive-emulator = automotiveAndroid.emulatorRunner;
          android-automotive32-emulator = automotive32Android.emulatorRunner;
          android-automotive32-canary-emulator = automotive32CanaryAndroid.emulatorRunner;
          android-automotive33-emulator = automotive33Android.emulatorRunner;
        };

        apps = {
          android-emulator = {
            type = "app";
            program = lib.getExe defaultAndroid.emulatorRunner;
          };

          android-list-images = {
            type = "app";
            program = lib.getExe defaultAndroid.androidListImages;
          };

          android-automotive-emulator = {
            type = "app";
            program = lib.getExe automotiveAndroid.emulatorRunner;
          };

          android-automotive32-emulator = {
            type = "app";
            program = lib.getExe automotive32Android.emulatorRunner;
          };

          android-automotive32-canary-emulator = {
            type = "app";
            program = lib.getExe automotive32CanaryAndroid.emulatorRunner;
          };

          android-automotive33-emulator = {
            type = "app";
            program = lib.getExe automotive33Android.emulatorRunner;
          };
        };

        devShells.android = config.mkAndroidShell {
          platformVersions = [
            "35"
            "36"
            "latest"
          ];
          emulatorPlatformVersion = "latest";
          ide = "android-studio";
        };

        devShells.android-emulator = config.mkAndroidShell {
          platformVersions = [ "latest" ];
          emulatorPlatformVersion = "latest";
          ide = null;
        };

        devShells.android-automotive = config.mkAndroidShell {
          platformVersions = [
            "33"
            "34x"
            "35x"
          ];
          emulatorPlatformVersion = "35x";
          preferredSystemImageTypes = [
            "android-automotive-playstore"
            "android-automotive"
          ];
          ide = "android-studio";
        };

        devShells.android-automotive32 = config.mkAndroidShell {
          platformVersions = [ "32" ];
          emulatorPlatformVersion = "32";
          repoJson = mergedRepoJson;
          emulatorVersion = "36.5.10";
          preferredSystemImageTypes = [ "android-automotive-playstore" ];
          androidEmulatorFlags = "-no-window -gpu swiftshader_indirect -no-audio -no-snapshot -accel on";
          ide = "android-studio";
        };

        devShells.android-automotive33 = config.mkAndroidShell {
          platformVersions = [ "33" ];
          emulatorPlatformVersion = "33";
          preferredSystemImageTypes = [ "android-automotive" ];
          androidEmulatorFlags = "-no-window -gpu swiftshader_indirect -no-snapshot -accel on";
          ide = "android-studio";
        };

        devShells.android-automotive32-canary = config.mkAndroidShell {
          platformVersions = [ "32" ];
          emulatorPlatformVersion = "32";
          repoJson = mergedRepoJson;
          emulatorVersion = "36.6.3";
          preferredSystemImageTypes = [ "android-automotive-playstore" ];
          androidEmulatorFlags = "-no-window -gpu swiftshader_indirect -no-audio -no-snapshot -accel on";
          ide = "android-studio";
        };

        devShells.android-intellij = config.mkAndroidShell {
          platformVersions = [ "35" ];
          emulatorPlatformVersion = "35";
          ide = "intellij";
          extraPackages = [ pkgs.sqlite ];
        };

        devShells.claude = config.mkAndroidShell {
          platformVersions = [ "35" ];
          emulatorPlatformVersion = "35";
          ide = "intellij";
          extraPackages = [ pkgs.sqlite ];
        };
      };
    };
}
