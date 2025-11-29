#!/usr/bin/env python3
"""
Database migration script for TasteThreads API.
Run this to apply all pending migrations.
"""

from dotenv import load_dotenv
load_dotenv()

import subprocess
import sys

def main():
    print("🚀 Running TasteThreads database migrations...")
    print()
    
    try:
        # Run alembic upgrade to latest
        result = subprocess.run(
            ["alembic", "upgrade", "head"],
            check=True,
            capture_output=True,
            text=True
        )
        
        print(result.stdout)
        if result.stderr:
            print(result.stderr)
        
        print()
        print("✅ Migrations completed successfully!")
        return 0
        
    except subprocess.CalledProcessError as e:
        print("❌ Migration failed!")
        print()
        print("STDOUT:", e.stdout)
        print("STDERR:", e.stderr)
        return 1
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())

