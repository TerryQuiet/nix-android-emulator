{ config, repoJson }:
{
  android = config.mkAndroidShell {
    platformVersions = [
      "35"
      "36"
      "latest"
    ];
    ide = "android-studio";
  };

  android-emulator = config.mkAndroidShell {
    platformVersions = [ "latest" ];
    systemImageTypes = [
      "google_apis_playstore"
      "google_apis"
      "default"
    ];
    ide = null;
  };

  android-automotive = config.mkAndroidShell {
    platformVersions = [
      "33"
      "34x"
      "35x"
    ];
    systemImageTypes = [
      "android-automotive-playstore"
      "android-automotive"
    ];
    ide = "android-studio";
  };

  android-automotive33 = config.mkAndroidShell {
    platformVersions = [ "33" ];
    systemImageTypes = [ "android-automotive" ];
    ide = "android-studio";
  };

  android-a32-33 = config.mkAndroidShell {
    emulatorVersion = "36.6.3";
    platformVersions = [
      "32"
      "33"
    ];
    repoJson = repoJson.mergedRepoJson;
    systemImageTypes = [
      "android-automotive-playstore"
      "android-automotive"
    ];
    # ide = "android-studio";
  };

  android-a32-33b = config.mkAndroidShell {
    # emulatorVersion = "36.6.3";
    platformVersions = [
      "32"
      "33"
    ];
    repoJson = repoJson.mergedRepoJson;
    systemImageTypes = [
      "android-automotive-playstore"
      "android-automotive"
    ];
    # ide = "android-studio";
  };

  android-intellij = config.mkAndroidShell {
    platformVersions = [ "35" ];
    ide = "intellij";
    includeNdk = true;
  };
}
