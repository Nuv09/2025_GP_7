import functions_framework
import requests
import json

@functions_framework.cloud_event
def farm_created(cloud_event):
    try:
        data = cloud_event.data
        resource = data.get("value", {}).get("name", "")
        farm_id = resource.split("/")[-1] if resource else ""
        
        if farm_id:
            service_url = "https://saaf-analyzer-us-120954850101.us-central1.run.app/analyze"
            response = requests.post(service_url, json={
                "data": {
                    "value": {
                        "name": f"projects/saaf-97251/databases/(default)/documents/farms/{farm_id}"
                    }
                }
            })
            print(f"✅ Triggered analysis for farm: {farm_id}, Status: {response.status_code}")
        else:
            print("❌ Could not extract farmId from event")
            
    except Exception as e:
        print(f"❌ Error in trigger: {e}")
