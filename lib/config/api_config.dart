/// Central place for the backend API base URL.
///
/// The app runs as Flutter Web, and the Flask backend
/// (see /backend/app.py) runs locally on port 5000 — so during
/// development both live on the same machine and `localhost` works.
///
/// If you deploy the backend elsewhere (a server, ngrok tunnel, etc.),
/// change this single constant — every network call in the app reads
/// from here.
const String kApiBaseUrl = 'http://localhost:5000';
