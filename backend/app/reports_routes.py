# app/reports_routes.py
import base64
import os
import logging
import pandas as pd
import arabic_reshaper
from bidi.algorithm import get_display
from fpdf import FPDF
from flask import Blueprint, jsonify
from google.cloud import firestore

# تعريف قاعدة البيانات محلياً داخل الملف لضمان الاستقلالية وكسر حلقة الاستيراد الدائرية
DB = firestore.Client()
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
    
    # تأكدي أن ملف الخط Cairo-Regular.ttf موجود في مسار app/fonts/
    font_path = os.path.join("app", "fonts", "Cairo-Regular.ttf")
    
    try:
        pdf.add_font("Cairo", fname=font_path)
    except:
        # حل احتياطي في حال تعذر العثور على الخط المخصص أثناء التطوير
        pdf.set_font("Arial", size=22)
    else:
        pdf.set_font("Cairo", size=22)

    # 1. الهيدر (أخضر سعف)
    pdf.set_text_color(20, 80, 20)
    pdf.cell(190, 20, txt=fix_arabic("تقرير حالة المزرعة الذكي - سعف"), ln=True, align='C')
    
    # 2. المعلومات الأساسية (Header)
    pdf.set_font("Cairo", size=12) if "Cairo" in pdf.fonts else pdf.set_font("Arial", size=12)
    pdf.set_text_color(0, 0, 0)
    header = export_data.get('header', {})
    
    pdf.ln(10)
    pdf.cell(95, 10, txt=fix_arabic(f"تاريخ التقرير: {header.get('date', '—')}"), align='L')
    pdf.cell(95, 10, txt=fix_arabic(f"اسم المزرعة: {header.get('name', '—')}"), ln=True, align='R')
    pdf.cell(190, 10, txt=fix_arabic(f"المساحة: {header.get('area', '—')}"), ln=True, align='R')

    # 3. مؤشر العافية
    pdf.ln(15)
    pdf.set_font("Cairo", size=18) if "Cairo" in pdf.fonts else pdf.set_font("Arial", size=18)
    score = export_data.get('wellness_score', 0)
    pdf.cell(190, 15, txt=fix_arabic(f"مؤشر العافية العام للمزرعة: {score}%"), ln=True, align='C')

    # 4. التوقعات (Forecast)
    pdf.ln(10)
    pdf.set_font("Cairo", size=11) if "Cairo" in pdf.fonts else pdf.set_font("Arial", size=11)
    forecast_txt = export_data.get('forecast', {}).get('text', "لا توجد توقعات حالية")
    pdf.multi_cell(190, 10, txt=fix_arabic(forecast_txt), align='R')

    file_path = "/tmp/farm_report.pdf"
    pdf.output(file_path)
    return file_path

# --- المسارات (Routes) ---

# 1. مسار تصدير الـ PDF
@reports_bp.route('/reports/<farm_id>/pdf', methods=['GET'])
def export_pdf(farm_id):
    try:
        farm_ref = DB.collection("farms").document(farm_id)
        doc = farm_ref.get()
        
        if not doc.exists:
            return jsonify({"ok": False, "error": "المزرعة غير موجودة"}), 404
            
        farm_data = doc.to_dict()
        export_data = farm_data.get('export_data') 
        
        if not export_data:
            return jsonify({"ok": False, "error": "البيانات غير جاهزة، يرجى تشغيل التحليل أولاً"}), 400

        pdf_path = generate_pdf_report(export_data)
        
        with open(pdf_path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode('utf-8')
            
        return jsonify({
            "ok": True, 
            "pdfBase64": encoded, 
            "fileName": f"Saaf_Report_{farm_id}.pdf"
        }), 200

    except Exception as e:
        logger.error(f"❌ Error in export_pdf: {e}")
        return jsonify({"ok": False, "error": str(e)}), 500

# 2. مسار تصدير الإكسل
@reports_bp.route('/reports/<farm_id>/excel', methods=['GET'])
def export_excel(farm_id):
    try:
        farm_ref = DB.collection("farms").document(farm_id)
        doc = farm_ref.get()
        
        if not doc.exists:
            return jsonify({"ok": False, "error": "المزرعة غير موجودة"}), 404
            
        export_data = doc.to_dict().get('export_data', {})
        
        if not export_data:
            return jsonify({"ok": False, "error": "البيانات غير جاهزة"}), 400

        # تجهيز جدول البيانات مع التأكد من مطابقة المسميات الصغيرة (ndvi, ndmi)
        data_table = {
            "المؤشر": ["اسم المزرعة", "المساحة", "تاريخ التحليل", "مؤشر العافية", "NDVI", "NDMI"],
            "القيمة": [
                export_data.get('header', {}).get('name', '—'),
                export_data.get('header', {}).get('area', '—'),
                export_data.get('header', {}).get('date', '—'),
                f"{export_data.get('wellness_score', 0)}%",
                export_data.get('biometrics', {}).get('ndvi', {}).get('val', '—'),
                export_data.get('biometrics', {}).get('ndmi', {}).get('val', '—')
            ]
        }

        df = pd.DataFrame(data_table)
        excel_path = f"/tmp/farm_data_{farm_id}.xlsx"
        df.to_excel(excel_path, index=False)

        with open(excel_path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode('utf-8')

        return jsonify({
            "ok": True, 
            "excelBase64": encoded, 
            "fileName": f"Saaf_Data_{farm_id}.xlsx"
        }), 200

    except Exception as e:
        logger.error(f"❌ Error in export_excel: {e}")
        return jsonify({"ok": False, "error": str(e)}), 500