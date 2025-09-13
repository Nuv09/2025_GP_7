class FarmsList {
  final String farmOwner, farmName, infectionAreas;
  final int numberOfPalm;
  //hello
  FarmsList({
    required this.farmOwner,
    required this.farmName,
    required this.numberOfPalm,
    required this.infectionAreas,
  });
}

//list of farms
List<FarmsList> farmlists = [
  FarmsList(
    farmOwner: "لطيفة الشريف",
    farmName: "مزرعة النخيل - الرياض",
    numberOfPalm: 250,
    infectionAreas: "الجزء الشمالي (15%)",
  ),

  FarmsList(
    farmOwner: "روان البطاطي",
    farmName: "واحة النخيل - القصيم",
    numberOfPalm: 400,
    infectionAreas: "لا توجد إصابة",
  ),

  FarmsList(
    farmOwner: "ولاء المطيري",
    farmName: "مزرعة الوادي الأخضر - الأحساء",
    numberOfPalm: 320,
    infectionAreas: "الحقل الغربي (8%)",
  ),

  FarmsList(
    farmOwner: "نوف العسكر",
    farmName: "مزرعة صحراء النخيل - وادي الدواسر",
    numberOfPalm: 380,
    infectionAreas: "الجزء الجنوبي (12%)",
  ),
];
