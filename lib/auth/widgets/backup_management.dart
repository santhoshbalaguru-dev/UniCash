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

// NEW IMPORT — getDriveFiles() and saveDriveFileToDevice() live in
// google_drive_service.dart after the split.
import 'package:unicash/auth/services/google_drive_service.dart';
// NEW IMPORT — loadBackup() and deleteBackup() live in backup_service.dart.
import 'package:unicash/auth/services/backup_service.dart';
// NEW IMPORT — convertBytesToMB() lives in utils/drive_utils.dart.
import 'package:unicash/auth/utils/drive_utils.dart';
// NEW IMPORT — LoadingShimmerDriveFiles was split into its own widget file.
import 'package:unicash/auth/widgets/loading_shimmer_drive_files.dart';

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
        filesState = filesState
            .where((file) => isSyncBackupFile(file.name))
            .toList();
        updateSettings(
          "devicesHaveBeenSynced",
          filesState.length,
          updateGlobalState: false,
        );
      }
    } else {
      if (filesState.length > 0) {
        filesState = filesState
            .where((file) => !isSyncBackupFile(file.name))
            .toList();
        updateSettings(
          "numBackups",
          filesState.length,
          updateGlobalState: false,
        );
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
                    await updateSettings(
                      "autoBackups",
                      value,
                      pagesNeedingRefresh: [],
                      updateGlobalState: false,
                    );
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
                    await updateSettings(
                      "backupSync",
                      value,
                      pagesNeedingRefresh: [],
                      updateGlobalState: false,
                    );
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
                      await updateSettings(
                        "syncEveryChange",
                        value,
                        pagesNeedingRefresh: [],
                        updateGlobalState: false,
                      );
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
                        "autoBackupsFrequency",
                        int.parse(value),
                        pagesNeedingRefresh: [],
                        updateGlobalState: false,
                      );
                    },
                    initial: appStateSettings["autoBackupsFrequency"]
                        .toString(),
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
                          await updateSettings(
                            "backupLimit",
                            int.parse(value),
                            updateGlobalState: false,
                          );
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
                      await updateSettings(
                        "backupLimit",
                        int.parse(value),
                        updateGlobalState: false,
                      );
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
                    for (
                      int i = 0;
                      i <
                          (widget.isClientSync
                              ? appStateSettings["devicesHaveBeenSynced"]
                              : appStateSettings["numBackups"]);
                      i++
                    )
                      LoadingShimmerDriveFiles(
                        isManaging: widget.isManaging,
                        i: i,
                      ),
                  ],
                )
              : SizedBox.shrink(),
          ...filesMap
              .map(
                (MapEntry<int, drive.File> file) => AnimatedSizeSwitcher(
                  child: deletedIndices.contains(file.key)
                      ? Container(key: ValueKey(1))
                      : Padding(
                          padding: const EdgeInsetsDirectional.only(
                            bottom: 8.0,
                          ),
                          child: Tappable(
                            onTap: () async {
                              if (!widget.isManaging) {
                                final result = await openPopup(
                                  context,
                                  title: "load-backup".tr(),
                                  subtitle:
                                      getWordedDateShortMore(
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
                                            .toLocal(),
                                      ),
                                  beforeDescriptionWidget: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      top: 8,
                                      bottom: 5,
                                    ),
                                    child: CodeBlock(
                                      text: (file.value.name ?? "No name"),
                                    ),
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
                                    context,
                                    driveApiState,
                                    file.value,
                                  );
                              }
                            },
                            borderRadius: 15,
                            color:
                                widget.isClientSync &&
                                    isCurrentDeviceSyncBackupFile(
                                      file.value.name,
                                    )
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.4)
                                : appStateSettings["materialYou"]
                                ? Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer
                                : getColor(
                                    context,
                                    "lightDarkAccentHeavyLight",
                                  ),
                            child: Container(
                              padding: EdgeInsetsDirectional.symmetric(
                                horizontal: 20,
                                vertical: 15,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(
                                          widget.isClientSync
                                              ? appStateSettings["outlinedIcons"]
                                                    ? Icons.devices_outlined
                                                    : Icons.devices_rounded
                                              : appStateSettings["outlinedIcons"]
                                              ? Icons.description_outlined
                                              : Icons.description_rounded,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.secondary,
                                          size: 30,
                                        ),
                                        SizedBox(
                                          width: widget.isClientSync ? 17 : 13,
                                        ),
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
                                                text:
                                                    (isSyncBackupFile(
                                                      file.value.name,
                                                    )
                                                    ? getDeviceFromSyncBackupFileName(
                                                            file.value.name,
                                                          ) +
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
                                                        const EdgeInsetsDirectional.only(
                                                          start: 8.0,
                                                        ),
                                                    child: Builder(
                                                      builder: (boxContext) {
                                                        return ButtonIcon(
                                                          color:
                                                              appStateSettings["materialYou"]
                                                              ? Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSecondaryContainer
                                                                    .withValues(
                                                                      alpha:
                                                                          0.08,
                                                                    )
                                                              : getColor(
                                                                  context,
                                                                  "lightDarkAccentHeavy",
                                                                ).withValues(
                                                                  alpha: 0.7,
                                                                ),
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
                                                      },
                                                    ),
                                                  ),
                                            Padding(
                                              padding:
                                                  const EdgeInsetsDirectional.only(
                                                    start: 5,
                                                  ),
                                              child: ButtonIcon(
                                                color:
                                                    appStateSettings["materialYou"]
                                                    ? Theme.of(context)
                                                          .colorScheme
                                                          .onSecondaryContainer
                                                          .withValues(
                                                            alpha: 0.08,
                                                          )
                                                    : getColor(
                                                        context,
                                                        "lightDarkAccentHeavy",
                                                      ).withValues(alpha: 0.7),
                                                onTap: () {
                                                  openPopup(
                                                    context,
                                                    icon:
                                                        appStateSettings["outlinedIcons"]
                                                        ? Icons.delete_outlined
                                                        : Icons.delete_rounded,
                                                    title: "delete-backup".tr(),
                                                    subtitle:
                                                        getWordedDateShortMore(
                                                          (file.value.modifiedTime ??
                                                                  DateTime.now())
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
                                                                  DateTime.now())
                                                              .toLocal(),
                                                        ),
                                                    beforeDescriptionWidget: Padding(
                                                      padding:
                                                          const EdgeInsetsDirectional.only(
                                                            top: 8,
                                                            bottom: 5,
                                                          ),
                                                      child: CodeBlock(
                                                        text:
                                                            (file.value.name ??
                                                                "No name") +
                                                            "\n" +
                                                            convertBytesToMB(
                                                              file.value.size ??
                                                                  "0",
                                                            ).toStringAsFixed(
                                                              2,
                                                            ) +
                                                            " MB",
                                                      ),
                                                    ),
                                                    description:
                                                        (widget.isClientSync
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
                                                        file.value.id ?? "",
                                                      );
                                                      openSnackbar(
                                                        SnackbarMessage(
                                                          title:
                                                              "deleted-backup"
                                                                  .tr(),
                                                          description:
                                                              (file
                                                                  .value
                                                                  .name ??
                                                              "No name"),
                                                          icon: Icons
                                                              .delete_rounded,
                                                        ),
                                                      );
                                                      setState(() {
                                                        deletedIndices.add(
                                                          file.key,
                                                        );
                                                      });
                                                      if (widget.isClientSync)
                                                        await updateSettings(
                                                          "devicesHaveBeenSynced",
                                                          appStateSettings["devicesHaveBeenSynced"] -
                                                              1,
                                                          updateGlobalState:
                                                              false,
                                                        );
                                                      if (widget.isManaging) {
                                                        await updateSettings(
                                                          "numBackups",
                                                          appStateSettings["numBackups"] -
                                                              1,
                                                          updateGlobalState:
                                                              false,
                                                        );
                                                      }
                                                      loadingIndeterminateKey
                                                          .currentState
                                                          ?.setVisibility(
                                                            false,
                                                          );
                                                    },
                                                    onSubmitLabel: "delete"
                                                        .tr(),
                                                    onCancel: () {
                                                      popRoute(context);
                                                    },
                                                    onCancelLabel: "cancel"
                                                        .tr(),
                                                  );
                                                },
                                                icon:
                                                    appStateSettings["outlinedIcons"]
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
