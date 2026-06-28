import 'package:unicash/colors.dart';
import 'package:unicash/struct/settings.dart';
import 'package:unicash/struct/randomConstants.dart';
import 'package:unicash/widgets/button.dart';
import 'package:unicash/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

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
      period: Duration(
        milliseconds: (1000 + randomDouble[i % 10] * 520).toInt(),
      ),
      baseColor: appStateSettings["materialYou"]
          ? Theme.of(context).colorScheme.secondaryContainer
          : getColor(context, "lightDarkAccentHeavyLight"),
      highlightColor: appStateSettings["materialYou"]
          ? Theme.of(
              context,
            ).colorScheme.secondaryContainer.withValues(alpha: 0.2)
          : getColor(
              context,
              "lightDarkAccentHeavy",
            ).withValues(alpha: 20 / 255),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 8.0),
        child: Tappable(
          onTap: () {},
          borderRadius: 15,
          color: appStateSettings["materialYou"]
              ? Theme.of(
                  context,
                ).colorScheme.secondaryContainer.withValues(alpha: 0.5)
              : getColor(
                  context,
                  "lightDarkAccentHeavy",
                ).withValues(alpha: 0.5),
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
                                  Radius.circular(5),
                                ),
                                color: Colors.white,
                              ),
                              height: 20,
                              width: 70 + randomDouble[i % 10] * 120 + 13,
                            ),
                            SizedBox(height: 6),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadiusDirectional.all(
                                  Radius.circular(5),
                                ),
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
                                : Icons.close_rounded,
                          ),
                          SizedBox(width: 5),
                          ButtonIcon(
                            onTap: () {},
                            icon: appStateSettings["outlinedIcons"]
                                ? Icons.close_outlined
                                : Icons.close_rounded,
                          ),
                        ],
                      )
                    : SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
