#!/usr/bin/env python3
"""Create or update an approved NeuroMathix teacher account.

Usage:
    python create_teacher.py \
      --service-account /secure/path/service-account.json \
      --email teacher@example.com \
      --password "StrongPassword123!" \
      --first-name Chameera \
      --last-name "De Silva" \
      --institution "SITC Campus"

The service-account JSON must remain outside the Git repository.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import auth, credentials, firestore


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create an approved Firebase teacher account for NeuroMathix."
    )
    parser.add_argument("--email", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--first-name", required=True)
    parser.add_argument("--last-name", required=True)
    parser.add_argument("--institution", default="")
    parser.add_argument(
        "--service-account",
        help="Path to a Firebase Admin service-account JSON file. "
        "When omitted, Application Default Credentials are used.",
    )
    parser.add_argument("--project-id", help="Optional Firebase project ID override.")
    parser.add_argument(
        "--disable-email-verification",
        action="store_true",
        help="Create the account without marking the email as verified.",
    )
    return parser.parse_args()


def initialize_admin(args: argparse.Namespace) -> None:
    options = {"projectId": args.project_id} if args.project_id else None
    service_account = args.service_account or os.getenv("GOOGLE_APPLICATION_CREDENTIALS")

    if service_account:
        path = Path(service_account).expanduser().resolve()
        if not path.is_file():
            raise FileNotFoundError(f"Service-account file not found: {path}")
        credential = credentials.Certificate(str(path))
        firebase_admin.initialize_app(credential, options)
    else:
        firebase_admin.initialize_app(options=options)


def main() -> int:
    args = parse_args()
    if len(args.password) < 8:
        print("Password must contain at least 8 characters.", file=sys.stderr)
        return 2

    initialize_admin(args)
    email = args.email.strip().lower()
    first_name = args.first_name.strip()
    last_name = args.last_name.strip()
    display_name = f"{first_name} {last_name}".strip()
    verified = not args.disable_email_verification

    try:
        user = auth.get_user_by_email(email)
        user = auth.update_user(
            user.uid,
            password=args.password,
            display_name=display_name,
            email_verified=verified,
            disabled=False,
        )
        action = "updated"
    except auth.UserNotFoundError:
        user = auth.create_user(
            email=email,
            password=args.password,
            display_name=display_name,
            email_verified=verified,
            disabled=False,
        )
        action = "created"

    existing_claims = user.custom_claims or {}
    auth.set_custom_user_claims(user.uid, {**existing_claims, "role": "teacher"})

    db = firestore.client()
    db.collection("users").document(user.uid).set(
        {
            "uid": user.uid,
            "firstName": first_name,
            "lastName": last_name,
            "displayName": display_name,
            "email": email,
            "emailLower": email,
            "role": "teacher",
            "institution": args.institution.strip(),
            "emailVerified": verified,
            "accountStatus": "active",
            "updatedAt": firestore.SERVER_TIMESTAMP,
            "createdAt": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )

    print(f"Teacher account {action} successfully.")
    print(f"UID: {user.uid}")
    print(f"Email: {email}")
    print("The teacher should sign out and sign in again to refresh role claims.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # concise CLI failure, without hiding the exception
        print(f"Error: {exc}", file=sys.stderr)
        raise
