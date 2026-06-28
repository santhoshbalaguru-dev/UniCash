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

// NEW IMPORT — googleUser lives in google_auth_service.dart after the split.
import 'package:unicash/auth/services/google_auth_service.dart';
// NEW IMPORT — signInAndSync() lives in backup_scheduler.dart after the split.
import 'package:unicash/auth/services/backup_scheduler.dart';

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
      pageNavigationFrameworkKey.currentState!.changePage(
        8,
        switchNavbar: true,
      );
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
            title: widget.forceButtonName ?? googleUser!.displayName ?? "",
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
