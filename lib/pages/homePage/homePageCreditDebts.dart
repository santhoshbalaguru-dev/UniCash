import 'package:unicash/colors.dart';
import 'package:unicash/database/tables.dart';
import 'package:unicash/pages/creditDebtTransactionsPage.dart';
import 'package:unicash/struct/databaseGlobal.dart';
import 'package:unicash/widgets/framework/popupFramework.dart';
import 'package:unicash/widgets/navigationFramework.dart';
import 'package:unicash/widgets/openBottomSheet.dart';
import 'package:unicash/widgets/periodCyclePicker.dart';
import 'package:unicash/widgets/util/keepAliveClientMixin.dart';
import 'package:unicash/widgets/transactionsAmountBox.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePageCreditDebts extends StatelessWidget {
  const HomePageCreditDebts({super.key});

  @override
  Widget build(BuildContext context) {
    return KeepAliveClientMixin(
      child: Padding(
        padding:
            const EdgeInsetsDirectional.only(bottom: 13, start: 13, end: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: TransactionsAmountBox(
                label: "lent".tr(),
                absolute: false,
                invertSign: true,
                totalWithCountStream: database.watchTotalWithCountOfCreditDebt(
                  allWallets: Provider.of<AllWallets>(context),
                  isCredit: true,
                  followCustomPeriodCycle: true,
                  cycleSettingsExtension: "CreditDebts",
                  selectedTab: null,
                ),
                totalWithCountStream2:
                    database.watchTotalWithCountOfCreditDebtLongTermLoansOffset(
                  allWallets: Provider.of<AllWallets>(context),
                  isCredit: true,
                  followCustomPeriodCycle: true,
                  cycleSettingsExtension: "CreditDebts",
                  selectedTab: null,
                ),
                textColor: getColor(context, "unPaidUpcoming"),
                openPage: CreditDebtTransactions(isCredit: true),
                onLongPress: () async {
                  await openCreditDebtsSettings(context);
                  homePageStateKey.currentState?.refreshState();
                },
              ),
            ),
            SizedBox(width: 13),
            Expanded(
              child: TransactionsAmountBox(
                label: "borrowed".tr(),
                absolute: false,
                totalWithCountStream: database.watchTotalWithCountOfCreditDebt(
                  allWallets: Provider.of<AllWallets>(context),
                  isCredit: false,
                  cycleSettingsExtension: "CreditDebts",
                  followCustomPeriodCycle: true,
                  selectedTab: null,
                ),
                totalWithCountStream2:
                    database.watchTotalWithCountOfCreditDebtLongTermLoansOffset(
                  allWallets: Provider.of<AllWallets>(context),
                  isCredit: false,
                  cycleSettingsExtension: "CreditDebts",
                  followCustomPeriodCycle: true,
                  selectedTab: null,
                ),
                textColor: getColor(context, "unPaidOverdue"),
                openPage: CreditDebtTransactions(isCredit: false),
                onLongPress: () async {
                  await openCreditDebtsSettings(context);
                  homePageStateKey.currentState?.refreshState();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future openCreditDebtsSettings(BuildContext context) {
  return openBottomSheet(
    context,
    PopupFramework(
      title: "loans".tr(),
      subtitle: "applies-to-homepage".tr(),
      child: PeriodCyclePicker(cycleSettingsExtension: "CreditDebts"),
    ),
  );
}
