import 'package:flutter/material.dart';
import 'package:saafapp/constant.dart';
import 'package:saafapp/farms/farmsList.dart';

class FarmCard extends StatelessWidget {
  final int farmIndex;
  final farmsList farmlist;

  const FarmCard({key, required this.farmIndex, required this.farmlist})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: defultPadding,
        vertical: defultPadding / 2,
      ),
      height: 190.0,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: 166.0,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: Beige,
              boxShadow: [
                BoxShadow(
                  offset: Offset(0, 15),
                  blurRadius: 25,
                  color: Colors.black45,
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
                      horizontal: defultPadding,
                    ),
                    child: Text(
                      farmlist.farmName,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  Spacer(),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: defultPadding,
                    ),
                    child: Text(
                      'المالك : ${farmlist.farmOwner}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: defultPadding,
                    ),
                    child: Text(
                      'مناطق الاصابه : ${farmlist.infectionAreas}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(defultPadding),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: defultPadding * 1.5, //30px
                        vertical: defultPadding / 5, //5px
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
