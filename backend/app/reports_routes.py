# app/reports_routes.py
import base64
import os
import logging
import pandas as pd
import arabic_reshaper
from bidi.algorithm import get_display
from fpdf import FPDF
from flask import Blueprint, jsonify
from app.firestore_utils import DB 

reports_bp = Blueprint("reports_bp", __name__)
logger = logging.getLogger(__name__)

# --- دالة إصلاح اللغة العربية للـ PDF ---
def fix_arabic(text):
    if not text: return ""
    reshaped_text = arabic_reshaper.reshape(str(text))
    return get_display(reshaped_text)

# --- دالة بناء الـ PDF الإبداعي ---
def generate_pdf_report(export_data):
    pdf = FPDF()
    pdf.add_page()
    # تأكدي أن اسم الملف يطابق الموجود في مجلد fonts عندك
    font_path = os.path.join("app", "fonts", "Cairo-Regular.ttf")
    pdf.add_font("Cairo", fname=font_path)
    pdf.set_font("Cairo", size=22)

    # الهيدر
    pdf.set_text_color(20, 80, 20)
    pdf.cell(190, 20, txt=fix_arabic("تقرير حالة المزرعة الذكي - سعف"), ln=True, align='C')
    
    # المعلومات الأساسية
    pdf.set_font("Cairo", size=12)
    pdf.set_text_color(0, 0, 0)
    header = export_data.get('header', {})
    pdf.ln(10)
    pdf.cell(95, 10, txt=fix_arabic(f"تاريخ التقرير: {header.get('date', '—')}"), align='L')
    pdf.cell(95, 10, txt=fix_arabic(f"اسم المزرعة: {header.get('name', '—')}"), ln=True, align='R')

    # مؤشر العافية
    pdf.ln(15)
    pdf.set_font("Cairo", size=18)
    score = export_data.get('wellness_score', 0)
    pdf.cell(190, 15, txt=fix_arabic(f"مؤشر العافية العام: {score}%"), ln=True, align='C')

    # التوقعات
    pdf.ln(10)
    pdf.set_font("Cairo", size=11)
    forecast_txt = export_data.get('forecast', {}).get('text', "لا توجد توقعات")
    pdf.multi_cell(190, 10, txt=fix_arabic(forecast_txt), align='R')

    file_path = "/tmp/farm_report.pdf"
    pdf.output(file_path)
    return file_path

# --- المسارات (Routes) ---

# 1. مسار الـ PDF
@reports_bp.route('/reports/<farm_id>/pdf', methods=['GET'])
def export_pdf(farm_id):
    try:
        farm_ref = DB.collection("farms").document(farm_id)
        doc = farm_ref.get()
        if not doc.exists: return jsonify({"ok": False, "error": "المزرعة غير موجودة"}), 404
        
        export_data = doc.to_dict().get('export_data')
        if not export_data: return jsonify({"ok": False, "error": "البيانات غير جاهزة"}), 400

        pdf_path = generate_pdf_report(export_data)
        with open(pdf_path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode('utf-8')
            
        return jsonify({"ok": True, "pdfBase64": encoded, "fileName": f"Saaf_{farm_id}.pdf"}), 200
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

# 2. مسار الإكسل
@reports_bp.route('/reports/<farm_id>/excel', methods=['GET'])
def export_excel(farm_id):
    try:
        farm_ref = DB.collection("farms").document(farm_id)
        export_data = farm_ref.get().to_dict().get('export_data', {})

        # تجهيز جدول البيانات
        data_table = {
            "المؤشر": ["اسم المزرعة", "المساحة", "تاريخ التحليل", "مؤشر العافية", "NDVI", "NDMI"],
            "القيمة": [
                export_data.get('header', {}).get('name'),
                export_data.get('header', {}).get('area'),
                export_data.get('header', {}).get('date'),
                f"{export_data.get('wellness_score')}%",
                export_data.get('biometrics', {}).get('ndvi', {}).get('val'),
                export_data.get('biometrics', {}).get('ndmi', {}).get('val')
            ]
        }

        df = pd.DataFrame(data_table)
        excel_path = "/tmp/farm_data.xlsx"
        df.to_excel(excel_path, index=False)

        with open(excel_path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode('utf-8')

        return jsonify({"ok": True, "excelBase64": encoded, "fileName": f"Saaf_Data_{farm_id}.xlsx"}), 200
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500