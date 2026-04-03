import 'dart:async';
import 'package:unicash/colors.dart';
import 'package:unicash/database/generatePreviewData.dart';
import 'package:unicash/database/tables.dart';
import 'package:unicash/firebase_options.dart';
import 'package:unicash/functions.dart';
import 'package:unicash/main.dart';
import 'package:unicash/pages/aboutPage.dart';
import 'package:unicash/pages/accountsPage.dart';
import 'package:unicash/struct/databaseGlobal.dart';
import 'package:unicash/struct/settings.dart';
import 'package:unicash/struct/shareBudget.dart';
import 'package:unicash/struct/syncClient.dart';
import 'package:unicash/widgets/animatedExpanded.dart';
import 'package:unicash/widgets/button.dart';
import 'package:unicash/widgets/exportCSV.dart';
import 'package:unicash/widgets/globalSnackbar.dart';
import 'package:unicash/widgets/importDB.dart';
import 'package:unicash/widgets/moreIcons.dart';
import 'package:unicash/widgets/navigationFramework.dart';
import 'package:unicash/widgets/navigationSidebar.dart';
import 'package:unicash/widgets/openBottomSheet.dart';
import 'package:unicash/widgets/openPopup.dart';
import 'package:unicash/widgets/openSnackbar.dart';
import 'package:unicash/widgets/framework/popupFramework.dart';
import 'package:unicash/widgets/settingsContainers.dart';
import 'package:unicash/widgets/tappable.dart';
import 'package:unicash/widgets/textWidgets.dart';
import 'package:unicash/widgets/util/saveFile.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/abusiveexperiencereport/v1.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/gmail/v1.dart' as gMail;
import 'package:google_sign_in/google_sign_in.dart' as signIn;
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:io';
import 'package:unicash/struct/randomConstants.dart';

Future<GoogleAuthClient> buildDriveAuthClient() async {
  final auth = await googleUser!.authorizationClient
      .authorizeScopes([drive.DriveApi.driveAppdataScope]);
  return GoogleAuthClient({
    'Authorization': 'Bearer ${auth.accessToken}',
    'X-Goog-AuthUser': '0',
  });
}

Future<bool> checkConnection() async {
  late bool isConnected;
  if (!kIsWeb) {
    try {
      final result = await InternetAddress.lookup('example.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        isConnected = true;
      }
    } on SocketException catch (e) {
      print(e.toString());
      isConnected = false;
    }
  } else {
    isConnected = true;
  }
  return isConnected;
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = new http.Client();
  GoogleAuthClient(this._headers);
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

// ---------------------------------------------------------------------------
// google_sign_in 7.2.0 API — key facts
//
//  • GoogleSignIn has NO unnamed constructor. Access it via GoogleSignIn.instance.
//  • Configuration is done once via GoogleSignIn.instance.initialize(clientId:).
//  • authenticate({scopeHint}) → Future<GoogleSignInAccount>  (direct, no wrapper)
//  • attemptLightweightAuthentication() → Future<GoogleSignInAccount?>?
//  • To get an http.Client for googleapis:
//      account.authorizationClient.authorizationForScopes(scopes)  // silent/cached
//      account.authorizationClient.authorizeScopes(scopes)         // interactive
//    Both return GoogleSignInClientAuthorization whose .httpClient is usable.
// ---------------------------------------------------------------------------

signIn.GoogleSignInAccount? googleUser;

// initialize() must be called exactly once before any other method.
bool _googleSignInInitialized = false;

List<String> _buildScopes({
  bool gMailPermissions = false,
  bool drivePermissionsAttachments = false,
}) {
  return [
    "https://www.googleapis.com/auth/userinfo.profile",
    "https://www.googleapis.com/auth/userinfo.email",
    drive.DriveApi.driveAppdataScope,
    if (drivePermissionsAttachments) drive.DriveApi.driveFileScope,
    if (gMailPermissions) ...[
      gMail.GmailApi.gmailReadonlyScope,
      gMail.GmailApi.gmailModifyScope,
    ],
  ];
}

Future<void> _ensureInitialized() async {
  if (_googleSignInInitialized) return;
  if (getPlatform() == PlatformOS.isIOS) {
    await signIn.GoogleSignIn.instance.initialize(
      clientId: DefaultFirebaseOptions.currentPlatform.iosClientId,
    );
  } else if (getPlatform() == PlatformOS.isAndroid) {
    // Android requires serverClientId — use the web client ID from
    // google-services.json / Firebase Console (not the Android client ID).
    await signIn.GoogleSignIn.instance.initialize(
      serverClientId: DefaultFirebaseOptions.currentPlatform.androidClientId,
    );
  } else {
    // Web reads clientId from index.html meta tags.
    await signIn.GoogleSignIn.instance.initialize();
  }
  _googleSignInInitialized = true;
}
// Obtain an authenticated http.Client scoped to [scopes] for the signed-in user.
// Tries the silent/cached path first; falls back to interactive authorization.
Future<http.Client?> _getAuthClient(List<String> scopes) async {
  if (googleUser == null) return null;
  try {
    signIn.GoogleSignInClientAuthorization? auth =
        await googleUser!.authorizationClient.authorizationForScopes(scopes);
    auth ??= await googleUser!.authorizationClient.authorizeScopes(scopes);
    return GoogleAuthClient({
      'Authorization': 'Bearer ${auth.accessToken}',
      'X-Goog-AuthUser': '0',
    });
  } catch (e) {
    print("_getAuthClient error: $e");
    try {
      final auth =
          await googleUser!.authorizationClient.authorizeScopes(scopes);
      return GoogleAuthClient({
        'Authorization': 'Bearer ${auth.accessToken}',
        'X-Goog-AuthUser': '0',
      });
    } catch (e2) {
      print("_getAuthClient retry error: $e2");
      return null;
    }
  }
}

Future<bool> signInGoogle(
    {BuildContext? context,
    bool? waitForCompletion,
    bool? gMailPermissions,
    bool? drivePermissionsAttachments,
    bool? silentSignIn,
    Function()? next}) async {
  if (await checkLockedFeatureIfInDemoMode(context) == false) return false;
  if (appStateSettings["emailScanning"] == false) gMailPermissions = false;

  try {
    if (gMailPermissions == true &&
        googleUser != null &&
        !(await testIfHasGmailAccess())) {
      await signOutGoogle();
      settingsPageStateKey.currentState?.refreshState();
    } else if (googleUser == null) {
      settingsPageStateKey.currentState?.refreshState();
    }

    if (waitForCompletion == true && context != null) openLoadingPopup(context);

    if (googleUser == null) {
      await _ensureInitialized();

      final List<String> scopes = _buildScopes(
        gMailPermissions: gMailPermissions == true,
        drivePermissionsAttachments: drivePermissionsAttachments == true,
      );

      signIn.GoogleSignInAccount? account;

      if (silentSignIn == true) {
        // attemptLightweightAuthentication returns Future<GoogleSignInAccount?>?
        // The method itself can return null on platforms that don't support it,
        // so we await the nullable future with ?.
        account =
            await signIn.GoogleSignIn.instance.attemptLightweightAuthentication();
      } else {
        // authenticate() returns Future<GoogleSignInAccount> directly in v7 —
        // not a result wrapper. Pass scopes as scopeHint for the consent screen.
        account = await signIn.GoogleSignIn.instance
            .authenticate(scopeHint: scopes);
      }

      if (account != null) {
        googleUser = account;
        await updateSettings("currentUserEmail", googleUser?.email ?? "",
            updateGlobalState: false);
        // Ensure all required scopes are authorized after authentication.
        await googleUser!.authorizationClient.authorizeScopes(scopes);
      } else {
        throw ("Login failed");
      }
    }

    if (waitForCompletion == true && context != null) popRoute(context);
    if (next != null) next();

    if (appStateSettings["hasSignedIn"] == false) {
      await updateSettings("hasSignedIn", true, updateGlobalState: false);
    }

    refreshUIAfterLoginChange();
    return true;
  } catch (e) {
    print(e);
    if (waitForCompletion == true && context != null) popRoute(context);
    openSnackbar(
      SnackbarMessage(
        title: "sign-in-error".tr(),
        description: "sign-in-error-description".tr(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.error_outlined
            : Icons.error_rounded,
        timeout: Duration(milliseconds: 3400),
        onTap: () => signInGoogle(
          context: context,
          drivePermissionsAttachments: drivePermissionsAttachments,
          gMailPermissions: gMailPermissions,
          next: next,
          silentSignIn: false,
          waitForCompletion: waitForCompletion,
        ),
      ),
    );
    googleUser = null;
    await updateSettings("currentUserEmail", "", updateGlobalState: false);
    if (runningCloudFunctions) {
      errorSigningInDuringCloud = true;
    } else {
      await updateSettings("hasSignedIn", false, updateGlobalState: false);
    }
    refreshUIAfterLoginChange();
    throw ("Error signing in");
  }
}

void refreshUIAfterLoginChange() {
  sidebarStateKey.currentState?.refreshState();
  accountsPageStateKey.currentState?.refreshState();
  settingsGoogleAccountLoginButtonKey.currentState?.refreshState();
}

Future<bool> testIfHasGmailAccess() async {
  print("TESTING GMAIL");
  try {
    final client = await _getAuthClient([
      gMail.GmailApi.gmailReadonlyScope,
      gMail.GmailApi.gmailModifyScope,
    ]);
    if (client == null) return false;
    gMail.GmailApi gmailApi = gMail.GmailApi(client);
    await gmailApi.users.messages
        .list(googleUser!.id.toString(), maxResults: 1);
  } catch (e) {
    print(e.toString());
    print("NO GMAIL");
    return false;
  }
  return true;
}

Future<bool> signOutGoogle() async {
  // v7: signOut() is on the singleton instance.
  await signIn.GoogleSignIn.instance.signOut();
  googleUser = null;
  await updateSettings("currentUserEmail", "", updateGlobalState: false);
  await updateSettings("hasSignedIn", false, updateGlobalState: false);
  refreshUIAfterLoginChange();
  print("Signedout");
  return true;
}

Future<bool> refreshGoogleSignIn() async {
  await signOutGoogle();
  await signInGoogle(silentSignIn: kIsWeb ? false : true);
  return true;
}

Future<bool> signInAndSync(BuildContext context,
    {required dynamic Function() next}) async {
  dynamic result = true;
  if (getPlatform() == PlatformOS.isIOS &&
      appStateSettings["hasSignedIn"] != true) {
    result = await openPopup(
      null,
      icon: appStateSettings["outlinedIcons"]
          ? Icons.badge_outlined
          : Icons.badge_rounded,
      title: "backups".tr(),
      description: "google-drive-backup-disclaimer".tr(),
      onSubmitLabel: "continue".tr(),
      onSubmit: () {
        popRoute(null, true);
      },
      onCancel: () {
        popRoute(null);
      },
      onCancelLabel: "cancel".tr(),
    );
  }

  if (result != true) return false;
  loadingIndeterminateKey.currentState?.setVisibility(true);
  try {
    await signInGoogle(
      context: context,
      waitForCompletion: false,
      next: next,
    );
    if (appStateSettings["username"] == "" && googleUser != null) {
      await updateSettings("username", googleUser?.displayName ?? "",
          pagesNeedingRefresh: [0], updateGlobalState: false);
    }
    if (googleUser != null) {
      loadingIndeterminateKey.currentState?.setVisibility(true);
      await syncData(context);
      loadingIndeterminateKey.currentState?.setVisibility(true);
      await syncPendingQueueOnServer();
      loadingIndeterminateKey.currentState?.setVisibility(true);
      await getCloudBudgets();
      loadingIndeterminateKey.currentState?.setVisibility(true);
      await createBackupInBackground(context);
    } else {
      throw ("cannot sync data - user not logged in");
    }
    loadingIndeterminateKey.currentState?.setVisibility(false);
    return true;
  } catch (e) {
    print("Error syncing data after login!");
    print(e.toString());
    loadingIndeterminateKey.currentState?.setVisibility(false);
    return false;
  }
}

Future<void> createBackupInBackground(context) async {
  if (appStateSettings["hasSignedIn"] == false) return;
  if (errorSigningInDuringCloud == true) return;
  if (kIsWeb && !entireAppLoaded) return;
  print("Last backup: " + appStateSettings["lastBackup"]);
  if (appStateSettings["autoBackups"] == true) {
    DateTime lastUpdate = DateTime.parse(appStateSettings["lastBackup"]);
    DateTime nextPlannedBackup = lastUpdate
        .add(Duration(days: appStateSettings["autoBackupsFrequency"]));
    print("next backup planned on " + nextPlannedBackup.toString());
    if (DateTime.now().millisecondsSinceEpoch >=
        nextPlannedBackup.millisecondsSinceEpoch) {
      print("auto backing up");

      bool hasSignedIn = false;
      if (googleUser == null) {
        hasSignedIn = await signInGoogle(
            context: context,
            gMailPermissions: false,
            waitForCompletion: false,
            silentSignIn: true);
      } else {
        hasSignedIn = true;
      }
      if (hasSignedIn == false) {
        return;
      }
      await createBackup(context, silentBackup: true, deleteOldBackups: true);
    } else {
      print("backup already made today");
    }
  }
  return;
}

Future forceDeleteDB() async {
  if (kIsWeb) {
    final html.Storage localStorage = html.window.localStorage;
    localStorage.clear();
  } else {
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dbFolder.path, 'db.sqlite'));
    await dbFile.delete();
  }
}

bool openDatabaseCorruptedPopup(BuildContext context) {
  if (isDatabaseCorrupted) {
    openPopup(
      context,
      icon: appStateSettings["outlinedIcons"]
          ? Icons.heart_broken_outlined
          : Icons.heart_broken_rounded,
      title: "database-corrupted".tr(),
      description: "database-corrupted-description".tr(),
      descriptionWidget: CodeBlock(
        text: databaseCorruptedError,
      ),
      barrierDismissible: false,
      onSubmit: () async {
        popRoute(context);
        await importDB(context, ignoreOverwriteWarning: true);
      },
      onSubmitLabel: "import-backup".tr(),
      onCancel: () async {
        popRoute(context);
        await openLoadingPopupTryCatch(() async {
          await forceDeleteDB();
          await sharedPreferences.clear();
        });
        restartAppPopup(context);
      },
      onCancelLabel: "reset".tr(),
    );
    lockAppWaitForRestart = true;
    appStateKey.currentState?.refreshAppState();
    return true;
  }
  return false;
}

Future<void> createBackup(
  context, {
  bool? silentBackup,
  bool deleteOldBackups = false,
  String? clientIDForSync,
}) async {
  try {
    if (silentBackup == false || silentBackup == null) {
      loadingIndeterminateKey.currentState?.setVisibility(true);
    }
    await backupSettings();
  } catch (e) {
    if (silentBackup == false || silentBackup == null) {
      maybePopRoute(context);
    }
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }

  try {
    if (deleteOldBackups)
      await deleteRecentBackups(context, appStateSettings["backupLimit"],
          silentDelete: true);

    DBFileInfo currentDBFileInfo = await getCurrentDBFileInfo();

    final client = await _getAuthClient([drive.DriveApi.driveAppdataScope]);
    if (client == null) throw ("Not authorized for Drive");
    final driveApi = drive.DriveApi(client);

    var media = new drive.Media(
        currentDBFileInfo.mediaStream, currentDBFileInfo.dbFileBytes.length);

    var driveFile = new drive.File();
    driveFile.name =
        "db-v$schemaVersionGlobal-${getCurrentDeviceName()}.sqlite";
    if (clientIDForSync != null)
      driveFile.name =
          getCurrentDeviceSyncBackupFileName(clientIDForSync: clientIDForSync);
    driveFile.modifiedTime = DateTime.now().toUtc();
    driveFile.parents = ["appDataFolder"];

    await driveApi.files.create(driveFile, uploadMedia: media);

    if (clientIDForSync == null)
      openSnackbar(
        SnackbarMessage(
          title: "backup-created".tr(),
          description: driveFile.name,
          icon: appStateSettings["outlinedIcons"]
              ? Icons.backup_outlined
              : Icons.backup_rounded,
        ),
      );
    if (clientIDForSync == null)
      await updateSettings("lastBackup", DateTime.now().toString(),
          pagesNeedingRefresh: [], updateGlobalState: false);

    if (silentBackup == false || silentBackup == null) {
      loadingIndeterminateKey.currentState?.setVisibility(false);
    }
  } catch (e) {
    if (silentBackup == false || silentBackup == null) {
      loadingIndeterminateKey.currentState?.setVisibility(false);
    }
    if (e is DetailedApiRequestError && e.status == 401) {
      await refreshGoogleSignIn();
    } else if (e is PlatformException) {
      await refreshGoogleSignIn();
    } else {
      openSnackbar(
        SnackbarMessage(
            title: e.toString(),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.error_outlined
                : Icons.error_rounded),
      );
    }
  }
}

Future<void> deleteRecentBackups(context, amountToKeep,
    {bool? silentDelete}) async {
  try {
    if (silentDelete == false || silentDelete == null) {
      loadingIndeterminateKey.currentState?.setVisibility(true);
    }

    final client = await _getAuthClient([drive.DriveApi.driveAppdataScope]);
    if (client == null) throw ("Not authorized for Drive");
    final driveApi = drive.DriveApi(client);

    drive.FileList fileList = await driveApi.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id, name, modifiedTime, size)',
    );
    List<drive.File>? files = fileList.files;
    if (files == null) {
      throw "No backups found.";
    }

    int index = 0;
    files.forEach((file) {
      if (index >= amountToKeep - 1) {
        if (!isSyncBackupFile(file.name)) deleteBackup(driveApi, file.id ?? "");
      }
      if (!isSyncBackupFile(file.name)) index++;
    });
    if (silentDelete == false || silentDelete == null) {
      loadingIndeterminateKey.currentState?.setVisibility(false);
    }
  } catch (e) {
    if (silentDelete == false || silentDelete == null) {
      loadingIndeterminateKey.currentState?.setVisibility(false);
    }
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }
}

Future<void> deleteBackup(drive.DriveApi driveApi, String fileId) async {
  try {
    await driveApi.files.delete(fileId);
  } catch (e) {
    openSnackbar(SnackbarMessage(title: e.toString()));
  }
}

Future<void> chooseBackup(context,
    {bool isManaging = false,
    bool isClientSync = false,
    bool hideDownloadButton = false}) async {
  try {
    openBottomSheet(
      context,
      BackupManagement(
        isManaging: isManaging,
        isClientSync: isClientSync,
        hideDownloadButton: hideDownloadButton,
      ),
    );
  } catch (e) {
    popRoute(context);
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }
}

Future<void> loadBackup(
    BuildContext context, drive.DriveApi driveApi, drive.File file) async {
  try {
    openLoadingPopup(context);

    await cancelAndPreventSyncOperation();

    List<int> dataStore = [];
    dynamic response = await driveApi.files
        .get(file.id ?? "", downloadOptions: drive.DownloadOptions.fullMedia);
    response.stream.listen(
      (data) {
        dataStore.insertAll(dataStore.length, data);
      },
      onDone: () async {
        await overwriteDefaultDB(Uint8List.fromList(dataStore));
        popRoute(context);
        await resetLanguageToSystem(context);
        await updateSettings("databaseJustImported", true,
            pagesNeedingRefresh: [], updateGlobalState: false);
        print(appStateSettings);
        openSnackbar(
          SnackbarMessage(
              title: "backup-restored".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.settings_backup_restore_outlined
                  : Icons.settings_backup_restore_rounded),
        );
        popRoute(context);
        restartAppPopup(
          context,
          description: kIsWeb
              ? "refresh-required-to-load-backup".tr()
              : "restart-required-to-load-backup".tr(),
        );
      },
      onError: (error) {
        openSnackbar(
          SnackbarMessage(
              title: error.toString(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.error_outlined
                  : Icons.error_rounded),
        );
      },
    );
  } catch (e) {
    popRoute(context);
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }
}

class GoogleAccountLoginButton extends StatefulWidget {
  const GoogleAccountLoginButton({
    super.key,
    this.navigationSidebarButton = false,
    this.isButtonSelected = false,
    this.isOutlinedButton = true,
    this.forceButtonName,
  });
  final bool navigationSidebarButton;
  final bool isButtonSelected;
  final bool isOutlinedButton;
  final String? forceButtonName;

  @override
  State<GoogleAccountLoginButton> createState() =>
      GoogleAccountLoginButtonState();
}

class GoogleAccountLoginButtonState extends State<GoogleAccountLoginButton> {
  void refreshState() {
    setState(() {});
  }

  void openPage({VoidCallback? onNext}) {
    if (widget.navigationSidebarButton) {
      pageNavigationFrameworkKey.currentState!
          .changePage(8, switchNavbar: true);
      appStateKey.currentState?.refreshAppState();
    } else {
      if (onNext != null) onNext();
    }
  }

  void loginWithSync({VoidCallback? onNext}) {
    signInAndSync(
      widget.navigationSidebarButton
          ? navigatorKey.currentContext ?? context
          : context,
      next: () {
        setState(() {});
        openPage(onNext: onNext);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.navigationSidebarButton == true) {
      return AnimatedSwitcher(
        duration: Duration(milliseconds: 600),
        child: googleUser == null
            ? getPlatform() == PlatformOS.isIOS
                ? NavigationSidebarButton(
                    key: ValueKey("login"),
                    label: "backup".tr(),
                    icon: MoreIcons.google_drive,
                    iconScale: 0.87,
                    onTap: loginWithSync,
                    isSelected: false,
                  )
                : NavigationSidebarButton(
                    key: ValueKey("login"),
                    label: "login".tr(),
                    icon: MoreIcons.google,
                    onTap: loginWithSync,
                    isSelected: false,
                  )
            : getPlatform() == PlatformOS.isIOS
                ? NavigationSidebarButton(
                    key: ValueKey("user"),
                    label: "backup".tr(),
                    icon: MoreIcons.google_drive,
                    iconScale: 0.87,
                    onTap: openPage,
                    isSelected: widget.isButtonSelected,
                  )
                : NavigationSidebarButton(
                    key: ValueKey("user"),
                    label: googleUser!.displayName ?? "",
                    icon: widget.forceButtonName == null
                        ? appStateSettings["outlinedIcons"]
                            ? Icons.person_outlined
                            : Icons.person_rounded
                        : MoreIcons.google_drive,
                    iconScale: widget.forceButtonName == null ? 1 : 0.87,
                    onTap: openPage,
                    isSelected: widget.isButtonSelected,
                  ),
      );
    }
    return googleUser == null
        ? getPlatform() == PlatformOS.isIOS
            ? SettingsContainerOpenPage(
                openPage: AccountsPage(),
                isOutlined: widget.isOutlinedButton,
                onTap: (openContainer) {
                  loginWithSync(onNext: openContainer);
                },
                title: widget.forceButtonName ?? "backup".tr(),
                icon: MoreIcons.google_drive,
                iconScale: 0.87,
              )
            : SettingsContainerOpenPage(
                openPage: AccountsPage(),
                isOutlined: widget.isOutlinedButton,
                onTap: (openContainer) {
                  loginWithSync(onNext: openContainer);
                },
                title: widget.forceButtonName ?? "login".tr(),
                icon: widget.forceButtonName == null
                    ? MoreIcons.google
                    : MoreIcons.google_drive,
                iconScale: widget.forceButtonName == null ? 1 : 0.87,
              )
        : getPlatform() == PlatformOS.isIOS
            ? SettingsContainerOpenPage(
                openPage: AccountsPage(),
                title: widget.forceButtonName ?? "backup".tr(),
                icon: MoreIcons.google_drive,
                isOutlined: widget.isOutlinedButton,
                iconScale: 0.87,
              )
            : SettingsContainerOpenPage(
                openPage: AccountsPage(),
                title: widget.forceButtonName ??
                    googleUser!.displayName ??
                    "",
                icon: widget.forceButtonName == null
                    ? appStateSettings["outlinedIcons"]
                        ? Icons.person_outlined
                        : Icons.person_rounded
                    : MoreIcons.google_drive,
                iconScale: widget.forceButtonName == null ? 1 : 0.87,
                isOutlined: widget.isOutlinedButton,
              );
  }
}

Future<(drive.DriveApi? driveApi, List<drive.File>?)> getDriveFiles() async {
  try {
    final client = await _getAuthClient([drive.DriveApi.driveAppdataScope]);
    if (client == null) throw ("Not authorized for Drive");
    drive.DriveApi driveApi = drive.DriveApi(client);

    drive.FileList fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        $fields: 'files(id, name, modifiedTime, size)');
    return (driveApi, fileList.files);
  } catch (e) {
    if (e is DetailedApiRequestError && e.status == 401) {
      await refreshGoogleSignIn();
      return await getDriveFiles();
    } else if (e is PlatformException) {
      await refreshGoogleSignIn();
      return await getDriveFiles();
    } else {
      openSnackbar(
        SnackbarMessage(
            title: e.toString(),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.error_outlined
                : Icons.error_rounded),
      );
    }
  }
  return (null, null);
}

class BackupManagement extends StatefulWidget {
  const BackupManagement({
    Key? key,
    required this.isManaging,
    required this.isClientSync,
    this.hideDownloadButton = false,
  }) : super(key: key);

  final bool isManaging;
  final bool isClientSync;
  final bool hideDownloadButton;

  @override
  State<BackupManagement> createState() => _BackupManagementState();
}

class _BackupManagementState extends State<BackupManagement> {
  List<drive.File> filesState = [];
  List<int> deletedIndices = [];
  late drive.DriveApi driveApiState;
  UniqueKey dropDownKey = UniqueKey();
  bool isLoading = true;
  bool autoBackups = appStateSettings["autoBackups"];
  bool backupSync = appStateSettings["backupSync"];

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {
      (drive.DriveApi?, List<drive.File>?) result = await getDriveFiles();
      drive.DriveApi? driveApi = result.$1;
      List<drive.File>? files = result.$2;
      if (files == null || driveApi == null) {
        setState(() {
          filesState = [];
          isLoading = false;
        });
      } else {
        setState(() {
          filesState = files;
          driveApiState = driveApi;
          isLoading = false;
        });
        bottomSheetControllerGlobal.snapToExtent(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isClientSync) {
      if (filesState.length > 0) {
        print(appStateSettings["devicesHaveBeenSynced"]);
        filesState =
            filesState.where((file) => isSyncBackupFile(file.name)).toList();
        updateSettings("devicesHaveBeenSynced", filesState.length,
            updateGlobalState: false);
      }
    } else {
      if (filesState.length > 0) {
        filesState =
            filesState.where((file) => !isSyncBackupFile(file.name)).toList();
        updateSettings("numBackups", filesState.length,
            updateGlobalState: false);
      }
    }
    Iterable<MapEntry<int, drive.File>> filesMap = filesState.asMap().entries;
    return PopupFramework(
      title: widget.isClientSync
          ? "devices".tr().capitalizeFirst
          : widget.isManaging
              ? "backups".tr()
              : "restore-a-backup".tr(),
      subtitle: widget.isClientSync
          ? "manage-syncing-info".tr()
          : widget.isManaging
              ? appStateSettings["backupLimit"].toString() +
                  " " +
                  "stored-backups".tr()
              : "overwrite-warning".tr(),
      child: Column(
        children: [
          widget.isClientSync && kIsWeb == false
              ? Row(
                  children: [
                    Expanded(
                      child: AboutInfoBox(
                        title: "web-app".tr(),
                        link: "https://budget-track.web.app/",
                        color: appStateSettings["materialYou"]
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : getColor(context, "lightDarkAccentHeavyLight"),
                        padding: EdgeInsetsDirectional.only(
                          start: 5,
                          end: 5,
                          bottom: 10,
                          top: 5,
                        ),
                      ),
                    ),
                  ],
                )
              : SizedBox.shrink(),
          widget.isManaging && widget.isClientSync == false
              ? SettingsContainerSwitch(
                  enableBorderRadius: true,
                  onSwitched: (value) async {
                    await updateSettings("autoBackups", value,
                        pagesNeedingRefresh: [], updateGlobalState: false);
                    setState(() {
                      autoBackups = value;
                    });
                  },
                  initialValue: appStateSettings["autoBackups"],
                  title: "auto-backups".tr(),
                  description: "auto-backups-description".tr(),
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_done_rounded,
                )
              : SizedBox.shrink(),
          widget.isClientSync
              ? SettingsContainerSwitch(
                  enableBorderRadius: true,
                  onSwitched: (value) async {
                    await updateSettings("backupSync", value,
                        pagesNeedingRefresh: [], updateGlobalState: false);
                    sidebarStateKey.currentState?.refreshState();
                    setState(() {
                      backupSync = value;
                    });
                  },
                  initialValue: appStateSettings["backupSync"],
                  title: "sync-data".tr(),
                  description: "sync-data-description".tr(),
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.cloud_sync_outlined
                      : Icons.cloud_sync_rounded,
                )
              : SizedBox.shrink(),
          widget.isClientSync && kIsWeb
              ? AnimatedExpanded(
                  expand: backupSync,
                  child: SettingsContainerSwitch(
                    enableBorderRadius: true,
                    onSwitched: (value) async {
                      await updateSettings("syncEveryChange", value,
                          pagesNeedingRefresh: [], updateGlobalState: false);
                    },
                    initialValue: appStateSettings["syncEveryChange"],
                    title: "sync-every-change".tr(),
                    descriptionWithValue: (value) {
                      return value
                          ? "sync-every-change-description1".tr()
                          : "sync-every-change-description2".tr();
                    },
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.all_inbox_outlined
                        : Icons.all_inbox_rounded,
                  ),
                )
              : SizedBox.shrink(),
          widget.isManaging && widget.isClientSync == false
              ? AnimatedExpanded(
                  expand: autoBackups,
                  child: SettingsContainerDropdown(
                    enableBorderRadius: true,
                    items: ["1", "2", "3", "7", "10", "14"],
                    onChanged: (value) async {
                      await updateSettings(
                          "autoBackupsFrequency", int.parse(value),
                          pagesNeedingRefresh: [], updateGlobalState: false);
                    },
                    initial:
                        appStateSettings["autoBackupsFrequency"].toString(),
                    title: "backup-frequency".tr(),
                    description: "number-of-days".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.event_repeat_outlined
                        : Icons.event_repeat_rounded,
                  ),
                )
              : SizedBox.shrink(),
          widget.isManaging &&
                  widget.isClientSync == false &&
                  appStateSettings["showBackupLimit"]
              ? SettingsContainerDropdown(
                  enableBorderRadius: true,
                  key: dropDownKey,
                  verticalPadding: 5,
                  title: "backup-limit".tr(),
                  icon: Icons.format_list_numbered_rtl_outlined,
                  initial: appStateSettings["backupLimit"].toString(),
                  items: ["10", "15", "20", "30"],
                  onChanged: (value) async {
                    if (int.parse(value) < appStateSettings["backupLimit"]) {
                      openPopup(
                        context,
                        icon: appStateSettings["outlinedIcons"]
                            ? Icons.delete_outlined
                            : Icons.delete_rounded,
                        title: "change-limit".tr(),
                        description: "change-limit-warning".tr(),
                        onSubmit: () async {
                          await updateSettings("backupLimit", int.parse(value),
                              updateGlobalState: false);
                          popRoute(context);
                        },
                        onSubmitLabel: "change".tr(),
                        onCancel: () {
                          popRoute(context);
                          setState(() {
                            dropDownKey = UniqueKey();
                          });
                        },
                        onCancelLabel: "cancel".tr(),
                      );
                    } else {
                      await updateSettings("backupLimit", int.parse(value),
                          updateGlobalState: false);
                    }
                  },
                )
              : SizedBox.shrink(),
          if ((widget.isManaging == false && widget.isClientSync == false) ==
              false)
            SizedBox(height: 10),
          isLoading
              ? Column(
                  children: [
                    for (int i = 0;
                        i <
                            (widget.isClientSync
                                ? appStateSettings["devicesHaveBeenSynced"]
                                : appStateSettings["numBackups"]);
                        i++)
                      LoadingShimmerDriveFiles(
                          isManaging: widget.isManaging, i: i),
                  ],
                )
              : SizedBox.shrink(),
          ...filesMap
              .map(
                (MapEntry<int, drive.File> file) => AnimatedSizeSwitcher(
                  child: deletedIndices.contains(file.key)
                      ? Container(
                          key: ValueKey(1),
                        )
                      : Padding(
                          padding:
                              const EdgeInsetsDirectional.only(bottom: 8.0),
                          child: Tappable(
                            onTap: () async {
                              if (!widget.isManaging) {
                                final result = await openPopup(
                                  context,
                                  title: "load-backup".tr(),
                                  subtitle: getWordedDateShortMore(
                                        (file.value.modifiedTime ??
                                                DateTime.now())
                                            .toLocal(),
                                        includeTime: true,
                                        includeYear: true,
                                        showTodayTomorrow: false,
                                      ) +
                                      "\n" +
                                      getWordedTime(
                                          navigatorKey.currentContext?.locale
                                              .toString(),
                                          (file.value.modifiedTime ??
                                                  DateTime.now())
                                              .toLocal()),
                                  beforeDescriptionWidget: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      top: 8,
                                      bottom: 5,
                                    ),
                                    child: CodeBlock(
                                        text: (file.value.name ?? "No name")),
                                  ),
                                  description: "load-backup-warning".tr(),
                                  icon: appStateSettings["outlinedIcons"]
                                      ? Icons.warning_outlined
                                      : Icons.warning_rounded,
                                  onSubmit: () async {
                                    popRoute(context, true);
                                  },
                                  onSubmitLabel: "load".tr(),
                                  onCancelLabel: "cancel".tr(),
                                  onCancel: () {
                                    popRoute(context);
                                  },
                                );
                                if (result == true)
                                  loadBackup(
                                      context, driveApiState, file.value);
                              }
                            },
                            borderRadius: 15,
                            color: widget.isClientSync &&
                                    isCurrentDeviceSyncBackupFile(
                                        file.value.name)
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.4)
                                : appStateSettings["materialYou"]
                                    ? Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer
                                    : getColor(
                                        context, "lightDarkAccentHeavyLight"),
                            child: Container(
                              padding: EdgeInsetsDirectional.symmetric(
                                  horizontal: 20, vertical: 15),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(
                                          widget.isClientSync
                                              ? appStateSettings[
                                                      "outlinedIcons"]
                                                  ? Icons.devices_outlined
                                                  : Icons.devices_rounded
                                              : appStateSettings[
                                                      "outlinedIcons"]
                                                  ? Icons.description_outlined
                                                  : Icons.description_rounded,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                          size: 30,
                                        ),
                                        SizedBox(
                                            width:
                                                widget.isClientSync ? 17 : 13),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              TextFont(
                                                text: getTimeAgo(
                                                  (file.value.modifiedTime ??
                                                          DateTime.now())
                                                      .toLocal(),
                                                ).capitalizeFirst,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                maxLines: 2,
                                              ),
                                              TextFont(
                                                text: (isSyncBackupFile(
                                                        file.value.name)
                                                    ? getDeviceFromSyncBackupFileName(
                                                            file.value.name) +
                                                        " " +
                                                        "sync"
                                                    : file.value.name ??
                                                        "No name"),
                                                fontSize: 14,
                                                maxLines: 2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  widget.isManaging
                                      ? Row(
                                          children: [
                                            widget.hideDownloadButton
                                                ? SizedBox.shrink()
                                                : Padding(
                                                    padding:
                                                        const EdgeInsetsDirectional
                                                            .only(
                                                      start: 8.0,
                                                    ),
                                                    child: Builder(
                                                        builder: (boxContext) {
                                                      return ButtonIcon(
                                                        color: appStateSettings[
                                                                "materialYou"]
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .onSecondaryContainer
                                                                .withValues(
                                                                    alpha: 0.08)
                                                            : getColor(context,
                                                                    "lightDarkAccentHeavy")
                                                                .withValues(
                                                                    alpha: 0.7),
                                                        onTap: () {
                                                          saveDriveFileToDevice(
                                                            boxContext:
                                                                boxContext,
                                                            driveApi:
                                                                driveApiState,
                                                            fileToSave:
                                                                file.value,
                                                          );
                                                        },
                                                        icon: Icons
                                                            .download_rounded,
                                                      );
                                                    }),
                                                  ),
                                            Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .only(start: 5),
                                              child: ButtonIcon(
                                                color: appStateSettings[
                                                        "materialYou"]
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .onSecondaryContainer
                                                        .withValues(alpha: 0.08)
                                                    : getColor(context,
                                                            "lightDarkAccentHeavy")
                                                        .withValues(alpha: 0.7),
                                                onTap: () {
                                                  openPopup(
                                                    context,
                                                    icon: appStateSettings[
                                                            "outlinedIcons"]
                                                        ? Icons.delete_outlined
                                                        : Icons.delete_rounded,
                                                    title: "delete-backup".tr(),
                                                    subtitle:
                                                        getWordedDateShortMore(
                                                              (file.value.modifiedTime ??
                                                                      DateTime
                                                                          .now())
                                                                  .toLocal(),
                                                              includeTime: true,
                                                              includeYear: true,
                                                              showTodayTomorrow:
                                                                  false,
                                                            ) +
                                                            "\n" +
                                                            getWordedTime(
                                                                navigatorKey
                                                                    .currentContext
                                                                    ?.locale
                                                                    .toString(),
                                                                (file.value.modifiedTime ??
                                                                        DateTime
                                                                            .now())
                                                                    .toLocal()),
                                                    beforeDescriptionWidget:
                                                        Padding(
                                                      padding:
                                                          const EdgeInsetsDirectional
                                                              .only(
                                                        top: 8,
                                                        bottom: 5,
                                                      ),
                                                      child: CodeBlock(
                                                        text: (file.value
                                                                    .name ??
                                                                "No name") +
                                                            "\n" +
                                                            convertBytesToMB(file
                                                                        .value
                                                                        .size ??
                                                                    "0")
                                                                .toStringAsFixed(
                                                                    2) +
                                                            " MB",
                                                      ),
                                                    ),
                                                    description: (widget
                                                            .isClientSync
                                                        ? "delete-sync-backup-warning"
                                                            .tr()
                                                        : null),
                                                    onSubmit: () async {
                                                      popRoute(context);
                                                      loadingIndeterminateKey
                                                          .currentState
                                                          ?.setVisibility(true);
                                                      await deleteBackup(
                                                          driveApiState,
                                                          file.value.id ?? "");
                                                      openSnackbar(
                                                        SnackbarMessage(
                                                            title:
                                                                "deleted-backup"
                                                                    .tr(),
                                                            description: (file
                                                                    .value
                                                                    .name ??
                                                                "No name"),
                                                            icon: Icons
                                                                .delete_rounded),
                                                      );
                                                      setState(() {
                                                        deletedIndices
                                                            .add(file.key);
                                                      });
                                                      if (widget.isClientSync)
                                                        await updateSettings(
                                                            "devicesHaveBeenSynced",
                                                            appStateSettings[
                                                                    "devicesHaveBeenSynced"] -
                                                                1,
                                                            updateGlobalState:
                                                                false);
                                                      if (widget.isManaging) {
                                                        await updateSettings(
                                                            "numBackups",
                                                            appStateSettings[
                                                                    "numBackups"] -
                                                                1,
                                                            updateGlobalState:
                                                                false);
                                                      }
                                                      loadingIndeterminateKey
                                                          .currentState
                                                          ?.setVisibility(
                                                              false);
                                                    },
                                                    onSubmitLabel:
                                                        "delete".tr(),
                                                    onCancel: () {
                                                      popRoute(context);
                                                    },
                                                    onCancelLabel:
                                                        "cancel".tr(),
                                                  );
                                                },
                                                icon: appStateSettings[
                                                        "outlinedIcons"]
                                                    ? Icons.close_outlined
                                                    : Icons.close_rounded,
                                              ),
                                            ),
                                          ],
                                        )
                                      : SizedBox.shrink(),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              )
              .toList(),
        ],
      ),
    );
  }
}

double convertBytesToMB(String bytesString) {
  try {
    int bytes = int.parse(bytesString);
    double megabytes = bytes / (1024 * 1024);
    return megabytes;
  } catch (e) {
    print("Error parsing bytes string: $e");
    return 0.0;
  }
}

class LoadingShimmerDriveFiles extends StatelessWidget {
  const LoadingShimmerDriveFiles({
    Key? key,
    required this.isManaging,
    required this.i,
  }) : super(key: key);

  final bool isManaging;
  final int i;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      period:
          Duration(milliseconds: (1000 + randomDouble[i % 10] * 520).toInt()),
      baseColor: appStateSettings["materialYou"]
          ? Theme.of(context).colorScheme.secondaryContainer
          : getColor(context, "lightDarkAccentHeavyLight"),
      highlightColor: appStateSettings["materialYou"]
          ? Theme.of(context)
              .colorScheme
              .secondaryContainer
              .withValues(alpha: 0.2)
          : getColor(context, "lightDarkAccentHeavy")
              .withValues(alpha: 20 / 255),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 8.0),
        child: Tappable(
          onTap: () {},
          borderRadius: 15,
          color: appStateSettings["materialYou"]
              ? Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withValues(alpha: 0.5)
              : getColor(context, "lightDarkAccentHeavy")
                  .withValues(alpha: 0.5),
          child: Container(
              padding:
                  EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          appStateSettings["outlinedIcons"]
                              ? Icons.description_outlined
                              : Icons.description_rounded,
                          color: Theme.of(context).colorScheme.secondary,
                          size: 30,
                        ),
                        SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadiusDirectional.all(
                                      Radius.circular(5)),
                                  color: Colors.white,
                                ),
                                height: 20,
                                width: 70 + randomDouble[i % 10] * 120 + 13,
                              ),
                              SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadiusDirectional.all(
                                      Radius.circular(5)),
                                  color: Colors.white,
                                ),
                                height: 14,
                                width: 90 + randomDouble[i % 10] * 120,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 13),
                  isManaging
                      ? Row(
                          children: [
                            ButtonIcon(
                                onTap: () {},
                                icon: appStateSettings["outlinedIcons"]
                                    ? Icons.close_outlined
                                    : Icons.close_rounded),
                            SizedBox(width: 5),
                            ButtonIcon(
                                onTap: () {},
                                icon: appStateSettings["outlinedIcons"]
                                    ? Icons.close_outlined
                                    : Icons.close_rounded),
                          ],
                        )
                      : SizedBox.shrink(),
                ],
              )),
        ),
      ),
    );
  }
}

Future<bool> saveDriveFileToDevice({
  required BuildContext boxContext,
  required drive.DriveApi driveApi,
  required drive.File fileToSave,
}) async {
  List<int> dataStore = [];
  dynamic response = await driveApi.files
      .get(fileToSave.id!, downloadOptions: drive.DownloadOptions.fullMedia);
  await for (var data in response.stream) {
    dataStore.insertAll(dataStore.length, data);
  }
  String fileName = "cashew-" +
      ((fileToSave.name ?? "") +
              cleanFileNameString(
                  (fileToSave.modifiedTime ?? DateTime.now()).toString()))
          .replaceAll(".sqlite", "") +
      ".sql";

  return await saveFile(
    boxContext: boxContext,
    dataStore: dataStore,
    dataString: null,
    fileName: fileName,
    successMessage: "backup-downloaded-success".tr(),
    errorMessage: "error-downloading".tr(),
  );
}

bool openBackupReminderPopupCheck(BuildContext context) {
  if ((appStateSettings["currentUserEmail"] == null ||
          appStateSettings["currentUserEmail"] == "") &&
      ((appStateSettings["numLogins"] + 1) % 7 == 0) &&
      appStateSettings["canShowBackupReminderPopup"] == true) {
    openPopup(
      context,
      icon: MoreIcons.google_drive,
      iconScale: 0.9,
      title: "backup-your-data-reminder".tr(),
      description: "backup-your-data-reminder-description".tr() +
          " " +
          "google-drive".tr(),
      onSubmitLabel: "backup".tr().capitalizeFirst,
      onSubmit: () async {
        popRoute(context);
        await signInAndSync(context, next: () {});
      },
      onCancelLabel: "never".tr().capitalizeFirst,
      onCancel: () async {
        popRoute(context);
        await updateSettings("canShowBackupReminderPopup", false,
            updateGlobalState: false);
      },
      onExtraLabel: "later".tr().capitalizeFirst,
      onExtra: () {
        popRoute(context);
      },
    );
    return true;
  }
  return false;
}