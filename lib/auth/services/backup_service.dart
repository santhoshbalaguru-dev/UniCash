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

// NEW IMPORT — getAuthClient() and refreshGoogleSignIn() now live in
// google_auth_service.dart after the split.
import 'package:unicash/auth/services/google_auth_service.dart';
// NEW IMPORT — overwriteDefaultDB / cancelAndPreventSyncOperation / etc. used
// by loadBackup() are assumed already exposed via the existing imports above
// (struct/syncClient.dart, struct/databaseGlobal.dart) exactly as in the
// original file, so no further additions were needed for those.

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
            : Icons.error_rounded,
      ),
    );
  }

  try {
    if (deleteOldBackups)
      await deleteRecentBackups(
        context,
        appStateSettings["backupLimit"],
        silentDelete: true,
      );

    DBFileInfo currentDBFileInfo = await getCurrentDBFileInfo();

    final client = await getAuthClient([drive.DriveApi.driveAppdataScope]);
    if (client == null) throw ("Not authorized for Drive");
    final driveApi = drive.DriveApi(client);

    var media = new drive.Media(
      currentDBFileInfo.mediaStream,
      currentDBFileInfo.dbFileBytes.length,
    );

    var driveFile = new drive.File();
    driveFile.name =
        "db-v$schemaVersionGlobal-${getCurrentDeviceName()}.sqlite";
    if (clientIDForSync != null)
      driveFile.name = getCurrentDeviceSyncBackupFileName(
        clientIDForSync: clientIDForSync,
      );
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
      await updateSettings(
        "lastBackup",
        DateTime.now().toString(),
        pagesNeedingRefresh: [],
        updateGlobalState: false,
      );

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
              : Icons.error_rounded,
        ),
      );
    }
  }
}

Future<void> deleteRecentBackups(
  context,
  amountToKeep, {
  bool? silentDelete,
}) async {
  try {
    if (silentDelete == false || silentDelete == null) {
      loadingIndeterminateKey.currentState?.setVisibility(true);
    }

    final client = await getAuthClient([drive.DriveApi.driveAppdataScope]);
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
            : Icons.error_rounded,
      ),
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

Future<void> loadBackup(
  BuildContext context,
  drive.DriveApi driveApi,
  drive.File file,
) async {
  try {
    openLoadingPopup(context);

    await cancelAndPreventSyncOperation();

    List<int> dataStore = [];
    dynamic response = await driveApi.files.get(
      file.id ?? "",
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    response.stream.listen(
      (data) {
        dataStore.insertAll(dataStore.length, data);
      },
      onDone: () async {
        await overwriteDefaultDB(Uint8List.fromList(dataStore));
        popRoute(context);
        await resetLanguageToSystem(context);
        await updateSettings(
          "databaseJustImported",
          true,
          pagesNeedingRefresh: [],
          updateGlobalState: false,
        );
        print(appStateSettings);
        openSnackbar(
          SnackbarMessage(
            title: "backup-restored".tr(),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.settings_backup_restore_outlined
                : Icons.settings_backup_restore_rounded,
          ),
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
                : Icons.error_rounded,
          ),
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
            : Icons.error_rounded,
      ),
    );
  }
}
