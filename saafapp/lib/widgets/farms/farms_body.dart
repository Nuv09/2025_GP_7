import 'package:flutter/material.dart';
import 'package:saafapp/constant.dart';
import 'package:saafapp/farms/farmsList.dart';
import 'package:saafapp/widgets/farms/farm_Card.dart';

//hello
class farmsBody extends StatelessWidget {
  const farmsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          SizedBox(height: defultPadding + 20),
          Expanded(
            child: Stack(
              children: [
                Container(
                  margin: EdgeInsets.only(top: 70.0),
                  decoration: BoxDecoration(
                    color: Beige,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(40),
                      topRight: Radius.circular(40),
                    ),
                  ),
                ),
                ListView.builder(
                  itemCount: farmlists.length,
                  itemBuilder: (context, index) =>
                      FarmCard(farmIndex: index, farmlist: farmlists[index]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
