# TasteThreads API

Backend API for TasteThreads. Uses Postgres, Redis, and Firebase.

## Local Setup

```bash
# Install dependencies
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Create .env file with Firebase vars
cat > .env << 'EOF'
DATABASE_URL=postgresql://user:password@localhost:5432/tastethreads
REDIS_URL=redis://localhost:6379
YELP_API_KEY=your_key_here
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
FIREBASE_CLIENT_EMAIL=firebase-adminsdk@your-project.iam.gserviceaccount.com
EOF

# Run migrations
python migrate.py

# Start server
uvicorn main:app --reload
```

## Railway Deploy

1. Create project on [railway.app](https://railway.app)
2. Add PostgreSQL database
3. Add Redis database
4. Add environment variables in Railway
5. Deploy the app
6. Run migrations manually: `railway run python migrate.py`
7. Generate domain in Settings → Networking

Server will start immediately after deploy.
