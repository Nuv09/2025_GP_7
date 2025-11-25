<p align="center">
  <img src="https://drive.google.com/uc?export=view&id=1xyQpMNmxZjCvjpjINZa33Q52WQm_0nLf" width="100%">
</p>

# 🌴 SAAF سعف – Intelligent Palm Tree Health Monitoring Platform  

## 📌 Introduction  
Palm trees are a vital agricultural and economic resource in Saudi Arabia and the Arab world. However, they face challenges such as **Red Palm Weevil infestations, water stress, and nutrient deficiencies**. Traditional inspection methods are often **time-consuming, costly, and limited in scale**, making early detection difficult.  

**SAAF** is a smart platform that leverages **satellite imagery and Artificial Intelligence (AI)** to monitor palm tree health and provide early detection of potential risks. The system supports farmers and agricultural organizations by reducing losses and improving farm management.  

## 🛠️ Technologies Used  
- **Frontend:** Flutter SDK  
- **Backend:** Python (Flask)  
- **APIs & Data Sources:** Google Earth Engine, Sentinel Hub API, Sentinel-2 & Landsat-8 satellite imagery  
- **AI & Data Science:** Machine Learning, Deep Learning (CNN), Vegetation Indices , Time-Series Analysis  
- **Database:** Firebase  
- **Visualization:** Interactive maps, dashboards, and reports  

## 🚀 Project Features  
- User registration & login
- Add and manage farms with GPS coordinates  
- Interactive map to view farm locations and palm health status  
- Automated analysis of satellite imagery and Vegetation Indices  
- AI-based classification of palm tree health (Healthy, Infected, Water Stress, Nutrient Deficiency)  
- Early warning and notification system  
- Admin dashboard for monitoring farms  
- Report generation (PDF/Excel)  


## ⚙️ Launching Instructions  
1. **Clone the repository:**  
   ```bash
   git clone https://github.com/Nuv09/2025_GP_7.git
   cd 2025_GP_7
   ```

2. **Backend Setup (Flask):**

No local backend setup is required.
The backend logic is fully deployed on Google Cloud Run.
Developers only need to update the Cloud Run API URL inside the Flutter app.

4. **Frontend Setup (Flutter):**  
   ```bash
   cd saafapp
   flutter pub get
   flutter run
   ```


5. **Database Setup:**

The Android Firebase configuration file google-services.json is already included in the project.
Firebase services (Firestore, Storage, Authentication) connect automatically—no additional configuration is required.
(If running on iOS, a GoogleService-Info.plist file would be required, but this project targets Android only.)
