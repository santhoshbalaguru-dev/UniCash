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
import 'package:universal_html/html.dart' as html;
import 'dart:io';
import 'package:unicash/struct/randomConstants.dart';

// NEW IMPORT — signInGoogle()/googleUser live in google_auth_service.dart.
import 'package:unicash/auth/services/google_auth_service.dart';
// NEW IMPORT — createBackup() lives in backup_service.dart.
import 'package:unicash/auth/services/backup_service.dart';
// NEW IMPORT — BackupManagement widget lives in widgets/google/backup_management.dart.
import 'package:unicash/auth/widgets/backup_management.dart';

// DECISION NOTE: chooseBackup() doesn't fit neatly into auth, drive, or
// recovery services — it's the entry point the UI calls to open the backup
// management/restore sheet, so it's grouped here alongside the other
// backup-flow orchestration functions.
Future<void> chooseBackup(
  context, {
  bool isManaging = false,
  bool isClientSync = false,
  bool hideDownloadButton = false,
}) async {
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
            : Icons.error_rounded,
      ),
    );
  }
}

Future<bool> signInAndSync(
  BuildContext context, {
  required dynamic Function() next,
}) async {
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
    await signInGoogle(context: context, waitForCompletion: false, next: next);
    if (appStateSettings["username"] == "" && googleUser != null) {
      await updateSettings(
        "username",
        googleUser?.displayName ?? "",
        pagesNeedingRefresh: [0],
        updateGlobalState: false,
      );
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
    DateTime nextPlannedBackup = lastUpdate.add(
      Duration(days: appStateSettings["autoBackupsFrequency"]),
    );
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
          silentSignIn: true,
        );
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
