#!/usr/bin/env python3
"""Envía el push de "nueva versión" al tema app-updates (FCM HTTP v1).

Lo usa .github/workflows/android.yml después de publicar la release. Los
teléfonos con la app y Google Play Services están suscritos a ese tema
(ver lib/core/push/push_service.dart); los que no, se enteran con la
comprobación periódica en segundo plano (UpdateCheckWorker).

Variables de entorno:
  FIREBASE_SERVICE_ACCOUNT  JSON de la cuenta de servicio (secreto de GitHub)
  MANIFEST                  ruta a latest.json (por defecto dist/latest.json)
  TOPIC                     tema (por defecto app-updates)
  PREVIOUS                  latest.json de la release anterior: si tiene el
                            mismo version_name no se avisa (la release se
                            publica en cada push a main; solo se notifica
                            cuando sube la versión del pubspec)
  FORCE=1                   avisa aunque no cambie version_name
  DRY_RUN=1                 imprime el mensaje sin enviarlo
"""
import json
import os
import sys

MANIFEST = os.environ.get("MANIFEST", "dist/latest.json")
TOPIC = os.environ.get("TOPIC", "app-updates")


def build_message(manifest: dict) -> dict:
    version = manifest.get("version_name") or str(manifest.get("version_code", ""))
    changes = [c for c in manifest.get("changes") or [] if c.strip()]
    body = changes[0] if changes else "Mejoras y correcciones."
    if len(body) > 140:
        body = body[:137].rstrip() + "…"
    body += " Toca para actualizar."
    return {
        "message": {
            "topic": TOPIC,
            "notification": {
                "title": f"Nueva versión de QvaTube {version}",
                "body": body,
            },
            # Los valores de data tienen que ser strings.
            "data": {
                "type": "app_update",
                "version_code": str(manifest.get("version_code", "")),
                "version_name": str(version),
            },
            "android": {
                "priority": "high",
                # Si el teléfono está apagado unos días le llega igual, pero
                # no un aviso de hace semanas.
                "ttl": "259200s",
                "collapse_key": "app-update",
                "notification": {
                    "channel_id": "qvatube_updates",
                    # Una versión nueva sustituye el aviso de la anterior.
                    "tag": "qvatube-update",
                },
            },
        }
    }


def previous_version_name() -> str | None:
    path = os.environ.get("PREVIOUS", "")
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f).get("version_name")
    except (OSError, ValueError):
        return None


def main() -> int:
    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    message = build_message(manifest)

    previous = previous_version_name()
    if previous and previous == manifest.get("version_name") and os.environ.get("FORCE") != "1":
        print(f">> Misma versión que la publicada ({previous}): no se envía push.")
        return 0

    if os.environ.get("DRY_RUN") == "1":
        print(json.dumps(message, ensure_ascii=False, indent=2))
        return 0

    raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "").strip()
    if not raw:
        print("::warning::Sin FIREBASE_SERVICE_ACCOUNT: no se envía el push de actualización.")
        return 0

    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account

    info = json.loads(raw)
    credentials = service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
    )
    session = AuthorizedSession(credentials)
    url = f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send"
    response = session.post(url, json=message, timeout=30)
    if response.status_code != 200:
        print(f"::error::FCM respondió {response.status_code}: {response.text}")
        return 1
    print(f">> Push de actualización enviado al tema '{TOPIC}': {response.json().get('name')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
