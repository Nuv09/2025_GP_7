import 'package:flutter/material.dart';
import 'package:saafapp/constant.dart';
import 'package:saafapp/farms/farms_list.dart';

class FarmCard extends StatelessWidget {
  final int farmIndex;
  final FarmsList farmlist;

  const FarmCard({super.key, required this.farmIndex, required this.farmlist});

  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: defaultPadding,
        vertical: defaultPadding / 2,
      ),
      height: 190.0,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: 166.0,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: beige,
              boxShadow: [
                BoxShadow(
                  offset: Offset(0, 15),
                  blurRadius: 25,
                  color: Colors.black45,
                ),
              ],
            ),
          ),
          // أزرار تعديل/حذف (يمين فوق) // NEW
          Positioned(
            bottom: 16,
            left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SmallActionButton(
                  icon: Icons.edit,
                  onPressed: () {}, // تعديل (أخضر فاتح)
                ),

                _SmallActionButton(
                  icon: Icons.delete_outline,
                  danger: true, // حذف (بني)
                  onPressed: () {},
                ),
              ],
            ),
          ),

          /*Positioned(
            top: 0.0,
            left: 0.0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: defultPadding),
              height: 160.0,
              width: 200.0,
              child: Image.asset('link', fit: BoxFit.cover),
            ),
          ),*/
          Positioned(
            bottom: 0.0,
            right: 0.0,
            child: SizedBox(
              height: 136,
              //because image is 200 width
              width: size.width - 100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Spacer(),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: defaultPadding,
                    ),
                    child: Text(
                      farmlist.farmName,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  Spacer(),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: defaultPadding,
                    ),
                    child: Text(
                      'المالك : ${farmlist.farmOwner}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: defaultPadding,
                    ),
                    child: Text(
                      'مناطق الاصابه : ${farmlist.infectionAreas}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(defaultPadding),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: defaultPadding * 1.5, //30px
                        vertical: defaultPadding / 5, //5px
                      ),
                      decoration: BoxDecoration(
                        color: goldColor,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text('عدد النخيل : ${farmlist.numberOfPalm}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ويدجت صغيرة لزر الإجراء // NEW
class _SmallActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger; // true = حذف (prownColor), false = تعديل (lightGreenColor)

  const _SmallActionButton({
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? prownColor : lightGreenColor;

    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: color), // أيقونة فقط بدون خلفية
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 18,
      // لا نستخدم styleFrom عشان ما تصير تعارضات أنماط/إصدارات
    );
  }
}
