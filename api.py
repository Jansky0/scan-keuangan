import os
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from scanner import scan_receipt, TransactionData
import tempfile
import shutil
from pathlib import Path

app = FastAPI(title="Finance Receipt Scanner API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def read_root():
    return {
        "status": "online",
        "message": "Finance Scanner API is ready. POST an image/pdf to /scan to extract transaction data."
    }

@app.post("/scan", response_model=TransactionData)
async def scan_endpoint(file: UploadFile = File(...)):
    # Simpan file sementara untuk diproses oleh scanner
    suffix = Path(file.filename).suffix if file.filename else ".jpg"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
        shutil.copyfileobj(file.file, temp_file)
        temp_path = temp_file.name

    try:
        data = scan_receipt(temp_path)
        return data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Bersihkan file temp
        if os.path.exists(temp_path):
            os.remove(temp_path)
