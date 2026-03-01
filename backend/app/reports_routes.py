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

# إعداد السجلات (Logging) لمراقبة السيرفر
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DB = firestore.Client()
# ملاحظة: إذا كنتِ ستستخدمين url_prefix في main.py، ابقيه كما هو هنا
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
    logger.info(f"🔍 [DEBUG] Starting search for farm with identifier: {identifier}")

    # 1. محاولة البحث بالـ Document ID
    try:
        doc_ref = DB.collection("farms").document(identifier).get()
        if doc_ref.exists:
            logger.info(f"✅ [SUCCESS] Farm found by Document ID: {identifier}")
            return doc_ref, "ID"
    except Exception as e:
        logger.error(f"Error fetching document: {e}")

    # 2. محاولة البحث بـ contractNumber
    logger.info(f"⚠️ [RETRY] Not found by ID. Searching by contractNumber field...")
    try:
        query = DB.collection("farms").where("contractNumber", "==", identifier).limit(1).get()
        docs = list(query)
        if docs:
            logger.info(f"✅ [SUCCESS] Farm found by contractNumber: {identifier}")
            return docs[0], "contractNumber"
    except Exception as e:
        logger.error(f"Error querying contractNumber: {e}")
    
    logger.error(f"❌ [FAILED] Farm {identifier} not found in Firestore by any method.")
    return None, None

def generate_pdf_report(export_data):
    """توليد ملف PDF مع المسار الصحيح للخطوط"""
    pdf = FPDF()
    pdf.add_page()
    
    # تحديد المسار للوصول لمجلد fonts الموجود بجانب مجلد app
    # current_dir هو مجلد app
    current_dir = os.path.dirname(os.path.abspath(__file__))
    # parent_dir هو المجلد الرئيسي (backend)
    parent_dir = os.path.dirname(current_dir)
    
    # تحديد مسار الخط (Cairo-Regular.ttf)
    font_path = os.path.join(parent_dir, "fonts", "Cairo-Regular.ttf")
    
    # التحقق من وجود الخط قبل محاولة استخدامه لضمان عدم توقف السيرفر
    if os.path.exists(font_path):
        try:
            pdf.add_font("Cairo", fname=font_path)
            pdf.set_font("Cairo", size=22)
            logger.info(f"✅ Custom font 'Cairo' loaded from: {font_path}")
        except Exception as e:
            logger.error(f"Error adding font: {e}")
            pdf.set_font("Arial", size=22)
    else:
        logger.warning(f"🚨 Font file NOT found at {font_path}. Falling back to Arial.")
        pdf.set_font("Arial", size=22)

    # العنوان
    pdf.set_text_color(20, 80, 20)
    pdf.cell(190, 20, txt=fix_arabic("تقرير حالة المزرعة الذكي - سعف"), ln=True, align='C')
    
    # بيانات الهيدر
    header = export_data.get('header', {})
    pdf.set_font("Arial", size=12)
    pdf.set_text_color(0, 0, 0)
    pdf.ln(10)
    
    # كتابة البيانات مع دعم العربي
    pdf.cell(95, 10, txt=fix_arabic(f"تاريخ التقرير: {header.get('date', '—')}"), align='R')
    pdf.cell(95, 10, txt=fix_arabic(f"اسم المزرعة: {header.get('name', '—')}"), ln=True, align='R')

    # مؤشر العافية
    score = export_data.get('wellness_score', 0)
    pdf.ln(15)
    pdf.set_font("Arial", 'B', 16)
    pdf.cell(190, 15, txt=fix_arabic(f"مؤشر العافية العام: {score}%"), ln=True, align='C')

    # حفظ الملف مؤقتاً
    file_path = "/tmp/farm_report.pdf"
    pdf.output(file_path)
    return file_path

@reports_bp.route('/reports/<farm_id>/pdf', methods=['GET'])
def export_pdf(farm_id):
    """API لتصدير ملف PDF مشفر بـ Base64"""
    try:
        doc, method = get_farm_safely(farm_id)
        
        if not doc:
            return jsonify({
                "ok": False, 
                "error": f"المزرعة ({farm_id}) غير موجودة. تأكد من الـ ID أو رقم العقد."
            }), 404
            
        farm_data = doc.to_dict()
        export_data = farm_data.get('export_data') 
        
        if not export_data:
            return jsonify({
                "ok": False, 
                "error": "بيانات التحليل (export_data) مفقودة. فضلاً اضغط 'بدء التحليل' في التطبيق أولاً."
            }), 400

        pdf_path = generate_pdf_report(export_data)
        
        with open(pdf_path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode('utf-8')
            
        return jsonify({
            "ok": True, 
            "pdfBase64": encoded, 
            "fileName": f"Saaf_Report_{farm_id}.pdf"
        }), 200

    except Exception as e:
        logger.error(f"💥 PDF Route Crash: {str(e)}")
        return jsonify({"ok": False, "error": f"Internal Server Error: {str(e)}"}), 500

@reports_bp.route('/reports/<farm_id>/excel', methods=['GET'])
def export_excel(farm_id):
    """API لتصدير بيانات المزرعة إلى ملف Excel"""
    try:
        doc, method = get_farm_safely(farm_id)
        
        if not doc:
            return jsonify({"ok": False, "error": f"المزرعة {farm_id} غير موجودة"}), 404
            
        export_data = doc.to_dict().get('export_data', {})
        if not export_data:
            return jsonify({"ok": False, "error": "بيانات الإكسل غير جاهزة لهذه المزرعة. الرجاء إجراء التحليل أولاً."}), 400

        # تجهيز الجدول
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
        
        # حفظ كملف Excel
        df.to_excel(excel_path, index=False)

        with open(excel_path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode('utf-8')

        return jsonify({
            "ok": True, 
            "excelBase64": encoded, 
            "fileName": f"Saaf_Data_{farm_id}.xlsx"
        }), 200

    except Exception as e:
        logger.error(f"💥 Excel Route Crash: {str(e)}")
        return jsonify({"ok": False, "error": f"Excel Error: {str(e)}"}), 500