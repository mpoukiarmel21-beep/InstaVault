#!/usr/bin/env python3
"""Download IPA from Gofile using API v2."""
import json
import sys
import time
import urllib.request
import urllib.error

def download_from_gofile(folder_code):
    print(f"Downloading from Gofile, folder code: {folder_code}")
    
    # Step 1: Get guest token
    print("Step 1: Getting guest token...")
    try:
        req = urllib.request.Request("https://api.gofile.io/guestToken")
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
        guest_token = data['data']['guestToken']
        print(f"  Token obtained: {guest_token[:8]}...")
    except Exception as e:
        print(f"  Failed to get guest token: {e}")
        sys.exit(1)
    
    # Step 2: Get content info
    print(f"Step 2: Getting content info for {folder_code}...")
    try:
        req = urllib.request.Request(
            f"https://api.gofile.io/contents/{folder_code}",
            headers={"Authorization": f"Bearer {guest_token}"}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
        print(f"  Status: {data.get('status')}")
        contents = data.get('data', {}).get('contents', {})
        print(f"  Found {len(contents)} file(s)")
    except Exception as e:
        print(f"  Failed to get content info: {e}")
        sys.exit(1)
    
    # Step 3: Find IPA file
    print("Step 3: Finding IPA file...")
    download_url = None
    for cid, c in contents.items():
        name = c.get('name', '')
        print(f"  - {name} ({c.get('size', 0) / 1024 / 1024:.1f} MB)")
        if name.endswith('.ipa') or 'application/zip' in c.get('mimetype', ''):
            download_url = c.get('link')
            break
    
    if not download_url:
        print("  Error: No IPA file found in folder")
        sys.exit(1)
    print(f"  Download URL: {download_url[:80]}...")
    
    # Step 4: Download
    print(f"Step 4: Downloading IPA...")
    output_path = "Input.ipa"
    try:
        req = urllib.request.Request(download_url)
        with urllib.request.urlopen(req, timeout=600) as resp:
            total = int(resp.headers.get('Content-Length', 0))
            downloaded = 0
            start = time.time()
            with open(output_path, 'wb') as f:
                while True:
                    chunk = resp.read(1024 * 1024)  # 1MB chunks
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    elapsed = time.time() - start
                    speed = downloaded / elapsed if elapsed > 0 else 0
                    pct = (downloaded / total * 100) if total > 0 else 0
                    print(f"\r  {downloaded / 1024 / 1024:.1f} MB / {total / 1024 / 1024:.1f} MB ({pct:.0f}%) - {speed / 1024 / 1024:.1f} MB/s", end="", flush=True)
            print()
    except Exception as e:
        print(f"\n  Download failed: {e}")
        sys.exit(1)
    
    import os
    size = os.path.getsize(output_path)
    print(f"  Downloaded: {output_path} ({size / 1024 / 1024:.1f} MB)")
    return output_path

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <folder_code>")
        sys.exit(1)
    download_from_gofile(sys.argv[1])
