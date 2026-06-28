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

// NEW IMPORT — getAuthClient() lives in google_auth_service.dart after the split.
import 'package:unicash/auth/services/google_auth_service.dart';
// NEW IMPORT — refreshGoogleSignIn() also lives in google_auth_service.dart.
// (already covered by the import above; both come from the same file)

Future<(drive.DriveApi? driveApi, List<drive.File>?)> getDriveFiles() async {
  try {
    final client = await getAuthClient([drive.DriveApi.driveAppdataScope]);
    if (client == null) throw ("Not authorized for Drive");
    drive.DriveApi driveApi = drive.DriveApi(client);

    drive.FileList fileList = await driveApi.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id, name, modifiedTime, size)',
    );
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
              : Icons.error_rounded,
        ),
      );
    }
  }
  return (null, null);
}

Future<bool> saveDriveFileToDevice({
  required BuildContext boxContext,
  required drive.DriveApi driveApi,
  required drive.File fileToSave,
}) async {
  List<int> dataStore = [];
  dynamic response = await driveApi.files.get(
    fileToSave.id!,
    downloadOptions: drive.DownloadOptions.fullMedia,
  );
  await for (var data in response.stream) {
    dataStore.insertAll(dataStore.length, data);
  }
  String fileName =
      "cashew-" +
      ((fileToSave.name ?? "") +
              cleanFileNameString(
                (fileToSave.modifiedTime ?? DateTime.now()).toString(),
              ))
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
