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

// NEW IMPORT — required because testIfHasGmailAccess() moved to gmail_service.dart
// but is still called from signInGoogle() below.
import 'package:unicash/auth/services/gmail_service.dart';

Future<GoogleAuthClient> buildDriveAuthClient() async {
  final auth = await googleUser!.authorizationClient.authorizeScopes([
    drive.DriveApi.driveAppdataScope,
  ]);
  return GoogleAuthClient({
    'Authorization': 'Bearer ${auth.accessToken}',
    'X-Goog-AuthUser': '0',
  });
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
//
// ALTERED: renamed from `_getAuthClient` (private) to `getAuthClient` (public).
// This rename was required by the split: it is now called from
// gmail_service.dart, google_drive_service.dart, and backup_service.dart, and
// Dart's leading-underscore privacy is scoped to the file, not the class, so
// the private name would not be visible outside this file anymore.
Future<http.Client?> getAuthClient(List<String> scopes) async {
  if (googleUser == null) return null;
  try {
    signIn.GoogleSignInClientAuthorization? auth = await googleUser!
        .authorizationClient
        .authorizationForScopes(scopes);
    auth ??= await googleUser!.authorizationClient.authorizeScopes(scopes);
    return GoogleAuthClient({
      'Authorization': 'Bearer ${auth.accessToken}',
      'X-Goog-AuthUser': '0',
    });
  } catch (e) {
    print("getAuthClient error: $e");
    try {
      final auth = await googleUser!.authorizationClient.authorizeScopes(
        scopes,
      );
      return GoogleAuthClient({
        'Authorization': 'Bearer ${auth.accessToken}',
        'X-Goog-AuthUser': '0',
      });
    } catch (e2) {
      print("getAuthClient retry error: $e2");
      return null;
    }
  }
}

Future<bool> signInGoogle({
  BuildContext? context,
  bool? waitForCompletion,
  bool? gMailPermissions,
  bool? drivePermissionsAttachments,
  bool? silentSignIn,
  Function()? next,
}) async {
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
        account = await signIn.GoogleSignIn.instance
            .attemptLightweightAuthentication();
      } else {
        // authenticate() returns Future<GoogleSignInAccount> directly in v7 —
        // not a result wrapper. Pass scopes as scopeHint for the consent screen.
        account = await signIn.GoogleSignIn.instance.authenticate(
          scopeHint: scopes,
        );
      }

      if (account != null) {
        googleUser = account;
        await updateSettings(
          "currentUserEmail",
          googleUser?.email ?? "",
          updateGlobalState: false,
        );
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
