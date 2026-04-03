import 'package:unicash/colors.dart';
import 'package:unicash/database/tables.dart';
import 'package:unicash/functions.dart';
import 'package:unicash/pages/addTransactionPage.dart';
import 'package:unicash/pages/homePage/homePageWalletSwitcher.dart';
import 'package:unicash/struct/currencyFunctions.dart';
import 'package:unicash/struct/databaseGlobal.dart';
import 'package:unicash/struct/settings.dart';
import 'package:unicash/widgets/navigationFramework.dart';
import 'package:unicash/widgets/tappable.dart';
import 'package:unicash/widgets/util/keepAliveClientMixin.dart';
import 'package:unicash/widgets/openBottomSheet.dart';
import 'package:unicash/widgets/walletEntry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:unicash/pages/addButton.dart';

class HomePageWalletList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const double borderRadius = 15;
    return KeepAliveClientMixin(
      child: Padding(
        padding:
            const EdgeInsetsDirectional.only(bottom: 13, start: 13, end: 13),
        child: Container(
          decoration: BoxDecoration(
            boxShadow: boxShadowCheck(boxShadowGeneral(context)),
            borderRadius: BorderRadiusDirectional.circular(borderRadius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadiusDirectional.circular(borderRadius),
            child: Tappable(
              color: getColor(context, "lightDarkAccentHeavyLight"),
              borderRadius: borderRadius,
              onLongPress: () async {
                await openBottomSheet(
                  context,
                  EditHomePagePinnedWalletsPopup(
                    homePageWidgetDisplay: HomePageWidgetDisplay.WalletList,
                    showCyclePicker: true,
                  ),
                  useCustomController: true,
                );
                homePageStateKey.currentState?.refreshState();
              },
              child: Column(
                children: [
                  StreamBuilder<List<WalletWithDetails>>(
                    stream: database.watchAllWalletsWithDetails(
                        homePageWidgetDisplay:
                            HomePageWidgetDisplay.WalletList),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            if (snapshot.hasData && snapshot.data!.length > 0)
                              SizedBox(height: 8),
                            for (WalletWithDetails walletDetails
                                in snapshot.data!)
                              WalletEntryRow(
                                selected: Provider.of<SelectedWalletPk>(context)
                                        .selectedWalletPk ==
                                    walletDetails.wallet.walletPk,
                                walletWithDetails: walletDetails,
                              ),
                            if (snapshot.hasData && snapshot.data!.length > 0)
                              SizedBox(height: 8),
                            if (snapshot.hasData && snapshot.data!.length <= 0)
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Expanded(
                                    child: AddButton(
                                      onTap: () async {
                                        await openBottomSheet(
                                          context,
                                          EditHomePagePinnedWalletsPopup(
                                            homePageWidgetDisplay:
                                                HomePageWidgetDisplay
                                                    .WalletList,
                                          ),
                                          useCustomController: true,
                                        );
                                        homePageStateKey.currentState
                                            ?.refreshState();
                                      },
                                      height: null,
                                      labelUnder: "account".tr(),
                                      icon: Icons.format_list_bulleted_add,
                                      padding: EdgeInsetsDirectional.symmetric(
                                          vertical: 10),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        );
                      }
                      return Container();
                    },
                  ),
                  if (appStateSettings["walletsListCurrencyBreakdown"] ==
                          true &&
                      Provider.of<AllWallets>(context)
                              .allContainSameCurrency() ==
                          false &&
                      Provider.of<AllWallets>(context)
                              .containsMultipleAccountsWithSameCurrency() ==
                          true)
                    HorizontalBreakAbove(
                      padding: EdgeInsetsDirectional.zero,
                      child: StreamBuilder<List<WalletWithDetails>>(
                        stream: database.watchAllWalletsWithDetails(
                            mergeLikeCurrencies: true),
                        builder: (context, snapshot) {
                          double totalAmountSpent = (snapshot.data ?? []).fold(
                              0.0, (double acc, WalletWithDetails wallet) {
                            return acc +
                                (wallet.totalSpent ?? 0.0) *
                                    amountRatioToPrimaryCurrency(
                                        Provider.of<AllWallets>(context),
                                        wallet.wallet.currency);
                          });

                          if (snapshot.hasData) {
                            return Column(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                if (snapshot.hasData &&
                                    snapshot.data!.length > 0)
                                  SizedBox(height: 8),
                                for (WalletWithDetails walletDetails
                                    in snapshot.data!)
                                  WalletEntryRow(
                                    selected: Provider.of<AllWallets>(context)
                                            .indexedByPk[appStateSettings[
                                                "selectedWalletPk"]]
                                            ?.currency ==
                                        walletDetails.wallet.currency,
                                    walletWithDetails: walletDetails,
                                    isCurrencyRow: true,
                                    percent: (totalAmountSpent == 0
                                                ? 0
                                                : ((walletDetails.totalSpent ??
                                                            0) *
                                                        amountRatioToPrimaryCurrency(
                                                            Provider.of<
                                                                    AllWallets>(
                                                                context),
                                                            walletDetails.wallet
                                                                .currency)) /
                                                    totalAmountSpent)
                                            .abs() *
                                        100
                                    // * ((walletDetails.totalSpent ?? 0) < 0
                                    //     ? -1
                                    //     : 1)
                                    ,
                                  ),
                                if (snapshot.hasData &&
                                    snapshot.data!.length > 0)
                                  SizedBox(height: 8),
                              ],
                            );
                          }
                          return Container();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
