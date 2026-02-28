# app/reports_routes.py
import base64
import os
import logging
import arabic_reshaper
from bidi.algorithm import get_display
from fpdf import FPDF
from flask import Blueprint, jsonify
from app.firestore_utils import DB # التأكد من استخدام Client الفايرستور الموحد

# تعريف الـ Blueprint لربطه بـ main.py
reports_bp = Blueprint("reports_bp", __name__)
logger = logging.getLogger(__name__)

# --- دالة إصلاح اللغة العربية ---
def fix_arabic(text):
    if not text: return ""
    reshaped_text = arabic_reshaper.reshape(str(text))
    return get_display(reshaped_text)

# --- دالة بناء الـ PDF الإبداعي ---
def generate_pdf_report(export_data):
    pdf = FPDF()
    pdf.add_page()
    
    # تحديد مسار الخط (Cairo) الذي قمتِ بتحميله
    # تأكدي أن اسم الملف في مجلد fonts هو Cairo-Regular.ttf
    font_path = os.path.join("app", "fonts", "Cairo-Regular.ttf")
    
    pdf.add_font("Cairo", fname=font_path)
    pdf.set_font("Cairo", size=22)

    # 1. الهيدر (أخضر فخم)
    pdf.set_text_color(20, 80, 20)
    pdf.cell(190, 20, txt=fix_arabic("تقرير حالة المزرعة الذكي - سعف"), ln=True, align='C')
    
    # 2. معلومات المزرعة (Header)
    pdf.set_font("Cairo", size=12)
    pdf.set_text_color(0, 0, 0)
    header = export_data.get('header', {})
    
    pdf.ln(10)
    pdf.cell(95, 10, txt=fix_arabic(f"تاريخ التقرير: {header.get('date', '—')}"), align='L')
    pdf.cell(95, 10, txt=fix_arabic(f"اسم المزرعة: {header.get('name', '—')}"), ln=True, align='R')
    pdf.cell(190, 10, txt=fix_arabic(f"المساحة الإجمالية: {header.get('area', '—')} متر مربع"), ln=True, align='R')

    # 3. مؤشر العافية (Wellness Score)
    pdf.ln(15)
    pdf.set_fill_color(240, 255, 240) # خلفية خضراء فاتحة جداً
    pdf.rect(10, pdf.get_y(), 190, 30, 'F')
    
    pdf.set_font("Cairo", size=18)
    score = export_data.get('wellness_score', 0)
    pdf.cell(190, 30, txt=fix_arabic(f"مؤشر العافية العام للمزرعة: {score}%"), ln=True, align='C')

    # 4. التوقعات (Forecast)
    pdf.ln(10)
    pdf.set_font("Cairo", size=14)
    pdf.set_text_color(20, 80, 20)
    pdf.cell(190, 10, txt=fix_arabic("توقعات النظام للأسبوع القادم:"), ln=True, align='R')
    
    pdf.set_font("Cairo", size=11)
    pdf.set_text_color(50, 50, 50)
    forecast_txt = export_data.get('forecast', {}).get('text', "لا توجد توقعات حالية")
    pdf.multi_cell(190, 10, txt=fix_arabic(forecast_txt), align='R')

    # حفظ الملف مؤقتاً في السيرفر
    file_path = "/tmp/farm_report.pdf" # استخدام مجلد tmp للملفات المؤقتة في Cloud Run
    pdf.output(file_path)
    return file_path

# --- المسار (Route) الذي يستقبله تطبيق فلوتر ---
@reports_bp.route('/reports/<farm_id>/pdf', methods=['GET'])
def export_pdf(farm_id):
    try:
        # 1. جلب البيانات من فايرستور باستخدام الـ ID
        farm_ref = DB.collection("farms").document(farm_id)
        doc = farm_ref.get()
        
        if not doc.exists:
            return jsonify({"ok": False, "error": "المزرعة غير موجودة"}), 404
            
        farm_data = doc.to_dict()
        export_data = farm_data.get('export_data') # البيانات المقشرة
        
        if not export_data:
            return jsonify({"ok": False, "error": "البيانات غير جاهزة، يرجى تشغيل التحليل أولاً"}), 400

        # 2. توليد الـ PDF
        pdf_path = generate_pdf_report(export_data)
        
        # 3. تحويله لـ Base64
        with open(pdf_path, "rb") as pdf_file:
            encoded_string = base64.b64encode(pdf_file.read()).decode('utf-8')
            
        fname = f"SAAF_Report_{farm_id}.pdf"
        return jsonify({
            "ok": True, 
            "fileName": fname, 
            "pdfBase64": encoded_string
        }), 200

    except Exception as e:
        logger.error(f"❌ Error in export_pdf: {e}")
        return jsonify({"ok": False, "error": str(e)}), 500