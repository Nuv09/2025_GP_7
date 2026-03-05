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

# إعداد السجلات (Logging)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DB = firestore.Client()
reports_bp = Blueprint("reports_bp", __name__)

def fix_arabic(text):
    """تحويل النص العربي ليظهر بشكل صحيح في الـ PDF"""
    if not text: return ""
    try:
        reshaped_text = arabic_reshaper.reshape(str(text))
        return get_display(reshaped_text)
    except Exception as e:
        logger.warning(f"Arabic Reshaper Error: {e}")
        return str(text)

def get_farm_safely(identifier):
    """البحث عن المزرعة في Firestore عبر الـ ID أو رقم العقد"""
    try:
        doc_ref = DB.collection("farms").document(identifier).get()
        if doc_ref.exists:
            return doc_ref, "ID"
    except Exception as e:
        logger.error(f"Error fetching document: {e}")

    try:
        query = DB.collection("farms").where("contractNumber", "==", identifier).limit(1).get()
        docs = list(query)
        if docs:
            return docs[0], "contractNumber"
    except Exception as e:
        logger.error(f"Error querying contractNumber: {e}")
    
    return None, None

def generate_pdf_report(export_data):
    """توليد ملف PDF بناءً على مسميات الصور في Firestore"""
    pdf = FPDF()
    pdf.add_page()
    
    # تحديد مسار الخط (مجلد fonts بجانب مجلد app)
    current_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(current_dir)
    font_path = os.path.join(parent_dir, "fonts", "Cairo-Regular.ttf")
    
    if os.path.exists(font_path):
        try:
            # ✅ الإصلاح 1: إضافة uni=True لدعم العربية
            pdf.add_font("Cairo", fname=font_path, uni=True)
            pdf.set_font("Cairo", size=22)
            logger.info(f"✅ Custom font 'Cairo' loaded from: {font_path}")
        except Exception as e:
            logger.error(f"Error adding font: {e}")
            pdf.set_font("Arial", size=22)
    else:
        logger.warning(f"🚨 Font file NOT found at {font_path}")
        pdf.set_font("Arial", size=22)

    # العنوان
    pdf.set_text_color(20, 80, 20)
    pdf.cell(190, 20, txt=fix_arabic("تقرير حالة المزرعة الذكي - سعف"), ln=True, align='C')
    
    # جلب البيانات بالمسميات الظاهرة في صورك (header, distribution, biometrics)
    header = export_data.get('header', {})
    dist = export_data.get('distribution', {})
    biometrics = export_data.get('biometrics', {})

    # ✅ الإصلاح 2: استخدام Cairo بدل Arial حتى يظهر النص العربي
    pdf.set_font("Cairo", size=12)
    pdf.set_text_color(0, 0, 0)
    pdf.ln(10)
    
    # مسميات الهيدر كما في الصورة: name, date, area
    pdf.cell(95, 10, txt=fix_arabic(f"تاريخ التقرير: {header.get('date', '—')}"), align='R')
    pdf.cell(95, 10, txt=fix_arabic(f"اسم المزرعة: {header.get('name', '—')}"), ln=True, align='R')
    pdf.cell(190, 10, txt=fix_arabic(f"المساحة الإجمالية: {header.get('area', '—')} م2"), ln=True, align='R')

    # مؤشر العافية من Healthy_Pct كما في الصورة
    wellness = dist.get('Healthy_Pct', 0)
    pdf.ln(15)
    # ✅ الإصلاح 2 (تكملة): Cairo بدل Arial
    pdf.set_font("Cairo", size=16)
    pdf.cell(190, 15, txt=fix_arabic(f"مؤشر العافية العام: {wellness:.1f}%"), ln=True, align='C')

    # عرض بيانات البيومتركس (ndvi, ndmi) بالأحرف الصغيرة كما في الصورة
    pdf.ln(10)
    # ✅ الإصلاح 2 (تكملة): Cairo بدل Arial
    pdf.set_font("Cairo", size=12)
    pdf.cell(190, 10, txt=fix_arabic(f"مؤشر الخضرة (NDVI): {biometrics.get('ndvi', {}).get('val', '—')}"), ln=True, align='R')
    pdf.cell(190, 10, txt=fix_arabic(f"مؤشر الرطوبة (NDMI): {biometrics.get('ndmi', {}).get('val', '—')}"), ln=True, align='R')

    file_path = "/tmp/farm_report.pdf"
    pdf.output(file_path)
    return file_path

@reports_bp.route('/reports/<farm_id>/pdf', methods=['GET'])
def export_pdf(farm_id):
    try:
        doc, method = get_farm_safely(farm_id)
        if not doc:
            return jsonify({"ok": False, "error": "المزرعة غير موجودة"}), 404
            
        farm_data = doc.to_dict()
        export_data = farm_data.get('export_data') 
        
        if not export_data:
            return jsonify({"ok": False, "error": "بيانات التحليل ناقصة في السجل."}), 400

        pdf_path = generate_pdf_report(export_data)
        with open(pdf_path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode('utf-8')
            
        return jsonify({"ok": True, "pdfBase64": encoded, "fileName": f"Saaf_Report_{farm_id}.pdf"}), 200
    except Exception as e:
        logger.error(f"💥 PDF Route Crash: {str(e)}")
        return jsonify({"ok": False, "error": str(e)}), 500

@reports_bp.route('/reports/<farm_id>/excel', methods=['GET'])
def export_excel(farm_id):
    try:
        doc, method = get_farm_safely(farm_id)
        if not doc:
            return jsonify({"ok": False, "error": "المزرعة غير موجودة"}), 404
            
        export_data = doc.to_dict().get('export_data', {})
        header = export_data.get('header', {})
        dist = export_data.get('distribution', {})
        biometrics = export_data.get('biometrics', {})

        data_table = {
            "المؤشر": ["اسم المزرعة", "المساحة", "تاريخ التحليل", "مؤشر العافية", "NDVI", "NDMI"],
            "القيمة": [
                header.get('name', '—'),
                header.get('area', '—'),
                header.get('date', '—'),
                f"{dist.get('Healthy_Pct', 0):.1f}%",
                biometrics.get('ndvi', {}).get('val', '—'),
                biometrics.get('ndmi', {}).get('val', '—')
            ]
        }

        df = pd.DataFrame(data_table)
        excel_path = f"/tmp/farm_{farm_id}.xlsx"
        # ✅ الإصلاح 3: xlsxwriter مع right_to_left للعربية
        with pd.ExcelWriter(excel_path, engine="xlsxwriter") as writer:
            df.to_excel(writer, index=False, sheet_name="تقرير المزرعة")
            worksheet = writer.sheets["تقرير المزرعة"]
            worksheet.right_to_left()

        with open(excel_path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode('utf-8')

        return jsonify({"ok": True, "excelBase64": encoded, "fileName": f"Saaf_Data_{farm_id}.xlsx"}), 200
    except Exception as e:
        logger.error(f"💥 Excel Route Crash: {str(e)}")
        return jsonify({"ok": False, "error": str(e)}), 500