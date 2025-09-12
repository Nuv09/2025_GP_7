class farmsList {
  final String farmOwner, farmName, infectionAreas;
  final int numberOfPalm;
  //hello
  farmsList({
    required this.farmOwner,
    required this.farmName,
    required this.numberOfPalm,
    required this.infectionAreas,
  });
}

//list of farms
List<farmsList> farmlists = [
  farmsList(
    farmOwner: "لطيفة الشريف",
    farmName: "مزرعة النخيل - الرياض",
    numberOfPalm: 250,
    infectionAreas: "الجزء الشمالي (15%)",
  ),

  farmsList(
    farmOwner: "روان البطاطي",
    farmName: "واحة النخيل - القصيم",
    numberOfPalm: 400,
    infectionAreas: "لا توجد إصابة",
  ),

  farmsList(
    farmOwner: "ولاء المطيري",
    farmName: "مزرعة الوادي الأخضر - الأحساء",
    numberOfPalm: 320,
    infectionAreas: "الحقل الغربي (8%)",
  ),

  farmsList(
    farmOwner: "نوف العسكر",
    farmName: "مزرعة صحراء النخيل - وادي الدواسر",
    numberOfPalm: 380,
    infectionAreas: "الجزء الجنوبي (12%)",
  ),
];
