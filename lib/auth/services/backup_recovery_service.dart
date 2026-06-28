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

// NOTE: forceDeleteDB() and openDatabaseCorruptedPopup() were grouped here
// (rather than backup_service.dart) since they deal with detecting/recovering
// from a corrupted local database, not with creating/restoring Drive backups.

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
      descriptionWidget: CodeBlock(text: databaseCorruptedError),
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
