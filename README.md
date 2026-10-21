<div align="center">

<img src="doc/banner.png" alt="QvaTube" width="100%">

# QvaTube — App Android

**Streaming cubano — películas, series, novelas, anime, música y libros en un solo lugar, hecho para Cuba.**

[![Build](https://github.com/R0ger0l1va/qvatube_apk/actions/workflows/android.yml/badge.svg)](https://github.com/R0ger0l1va/qvatube_apk/actions/workflows/android.yml)
[![Release](https://img.shields.io/badge/release-Apk%20%E2%9%93%20latest-blue)](https://github.com/R0ger0l1va/qvatube_apk/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569A?logo=flutter&logoColor=white)](https://docs.flutter.dev)
[![Android](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![API](https://img.shields.io/badge/API-QvaTube%20v1-FF3D1A)](doc/openapi.json)
[![License](https://img.shields.io/badge/license-MIT-6B6B70)](LICENSE)

[**⬇ Descargar la APK**](https://github.com/R0ger0l1va/qvatube_apk/releases/latest/download/qvatube.apk) ·
[**⬇ Todas las versiones**](https://github.com/R0ger0l1va/qvatube_apk/releases) ·
[**Documentación de la API**](doc/API_MAP.md) ·
[**Guía de CI/CD y Play Store**](doc/CI_CD.md)

</div>

---

## 📱 Qué es esta app

QvaTube es el cliente **Android nativo** de la plataforma de streaming QvaTube. Lleva
el catálogo completo (casi 20.000 títulos) a un teléfono con pantalla pequeña y conexiones
lentas: tema oscuro cinematográfico, un solo color de acento, tipografías condensadas y
descargas optimizadas para gastar lo mínimo de datos.

<div align="center">
<img src="doc/screenshots/login.png" width="24%" alt="Login">
<img src="doc/screenshots/home.png" width="24%" alt="Home">
<img src="doc/screenshots/musica.png" width="24%" alt="Música">
<img src="doc/screenshots/libros.png" width="24%" alt="Libros">
</div>

---

## ✨ Funcionalidades

| | Pantalla | Qué hace |
|---|---|---|
| 🔐 | **Introducción** | Se muestra **solo la primera vez**: resumen de la app, logo y opción de cerrar. |
| 🔐 | **Login / Registro** | Email + contraseña, recuperación por Telegram, OTP de 6 casillas, modo invitado y vinculación con Telegram. |
| 🏠 | **Inicio** | Hero con acciones rápidas, carruseles de "Seguir donde quedaste", recomendaciones de temporada y filas por género. |
| 🔥 | **Popular** | Lo más visto de la comunidad, con cinta "NUEVO" y contador de popularidad. |
| 📺 | **Televisión** | Canales en vivo (pendiente de endpoint en el backend). |
| 🎬 | **Películas / Series / Anime / Novelas** | Catálogo completo con filtro por género, orden Recientes/A-Z y scroll infinito. |
| 🎵 | **Música** | Álbumes con carátula cuadrada, artista y número de pistas. |
| 📖 | **Libros** | Libros en EPUB/PDF con portada y tamaño del archivo. |
| 👤 | **Mi perfil** | Datos de la cuenta, plan, código de referido, foto de perfil y vinculación con Telegram. |
| 💳 | **Plan y suscripción** | Consumo del plan (descargas, streams, música) y catálogo de planes CUP/USD. |
| 🔔 | **Notificaciones** | Avisos de la cuenta, marcar como leídas y borrar. |
| ❤️ | **Favoritos** | Contenido guardado por el usuario. |
| 💬 | **Comunidad** | Enlace a WhatsApp, bot de Telegram y datos de pago por Transfermóvil. |
| ⚙️ | **Configuración** | Preferencias locales (cinta "NUEVO", fila "Seguir donde quedaste"). |

### 🎃 Temas por temporada

Los logos, favicons e iconos se cambian **sin tocar código**: todo está
centralizado en [`assets/theme.json`](assets/theme.json) (tema activo + variantes)
y se puede cambiar en caliente desde *Configuración → Temporada*.

```bash
# Ver los temas disponibles
dart run tool/apply_theme.dart --list

# Cambiar de temporada (manifiesto + icono del launcher)
dart run tool/apply_theme.dart halloween --sync-pubspec
```

Guía completa para añadir una nueva temporada: [`doc/TEMAS.md`](doc/TEMAS.md)

### 🎨 Sistema de diseño

- **Dark theme** cinematográfico (`#0A0A0B`) con un único acento rojo-naranja (`#FF3D1A`).
- **Bebas Neue** para títulos y textos grandes, **Inter** para el cuerpo, **Roboto Mono** para
  tamaños de archivo, OTP y duraciones (empaquetadas en `assets/fonts`).
- Barra inferior con **9 secciones** y **Inicio siempre en el medio**, indicador activo en
  forma de óvalo con glow respiratorio.
- Tarjetas 2:3 (1:1 en música), cinta "NUEVO", badge de tamaño/episodios y barra de progreso.

---

## ⬇️ Cómo obtener la APK (paso a paso)

Cada vez que se sube código a la rama `main`, GitHub Actions compila la app y actualiza una
release con el APK firmado. El enlace **siempre** apunta a la última versión:

### Opción 1 — desde el navegador (la más fácil)

1. Abre la sección **Releases** del repositorio:
   👉 https://github.com/R0ger0l1va/qvatube_apk/releases
2. En **"QvaTube (última versión)"** descarga el archivo **`qvatube.apk`** (~26 MB).
   - Es el APK de release **solo arm64-v8a** (Android 7+ de 64 bits, el 99 % de
     los teléfonos activos), minificado con R8 y con el código de Dart ofuscado.
   - Si necesitas 32 bits, compílalo tú con `--split-per-abi` (ver §Opción 4).
3. En el teléfono, abre el archivo descargado y acepta **"Instalar apps de orígenes
   desconocidos"** para tu navegador o gestor de archivos.
4. Listo: QvaTube aparece en el launcher con el icono de la marca.

### Opción 2 — enlace directo (ideal para compartir)

Copia y pega este enlace; siempre descarga la última versión publicada:

```
https://github.com/R0ger0l1va/qvatube_apk/releases/latest/download/qvatube.apk
```

Puedes ponerlo en la web, en un grupo de Telegram o en el botón **"Descargar APK"** de la
propia app.

> ℹ️ **Si el repositorio es privado**, quien no tenga acceso a él verá un `404` al
> seguir el enlace. En ese caso: o pasas el repositorio a **público**, o sirves el APK
> desde tu propio dominio (el backend ya expone `/download/qvatube.apk`, que puedes
> apuntar a la release de GitHub) o compartes el `.apk` por Telegram.

### Opción 3 — desde la terminal

```bash
# Bajar el APK universal a tu ordenador
curl -L -o qvatube.apk \
  https://github.com/R0ger0l1va/qvatube_apk/releases/latest/download/qvatube.apk

# Instalarlo en un teléfono conectado por USB
adb install -r qvatube.apk
```

### Opción 4 — compilarlo tú mismo

```bash
git clone https://github.com/R0ger0l1va/qvatube_apk.git
cd qvatube_apk
flutter pub get
flutter run                     # en un dispositivo o emulador

# APK de release tal cual lo publica la CI (arm64, minificado y ofuscado)
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --obfuscate --split-debug-info=build/symbols
# -> build/app/outputs/flutter-apk/app-arm64-v8a-release.apk  (~26 MB)

# AAB para Google Play (con todas las arquitecturas)
flutter build appbundle --release
```

> Requiere Flutter 3.47+ y JDK 17. Para compilar con la **clave de release** tienes que
> crear `android/key.properties` (ver [`doc/CI_CD.md`](doc/CI_CD.md)).

---

## 🔌 Servidor y configuración

La app consume la **API de QvaTube** (`https://qvatube.hidenplay.net/`, especificación en
[`doc/openapi.json`](doc/openapi.json)).

```bash
# Apuntar a otro servidor
flutter run --dart-define=API_URL=https://otro-servidor/
```

| Archivo | Para qué sirve |
|---|---|
| `lib/core/config/app_config.dart` | URL de la API y el interruptor `remoteCallsEnabled`. |
| `lib/core/network/api_client.dart` | Cliente HTTP, cookie de sesión `qva_session` y manejo de errores. |
| `lib/features/auth/` | Login, registro, recuperación, verificación por Telegram, perfil y avatar. |
| `lib/features/catalog/` | Catálogo, home, planes, notificaciones y favoritos. |

**Mapa completo endpoint ↔ pantalla:** [`doc/API_MAP.md`](doc/API_MAP.md)

> La app funciona **sin cuenta** en modo invitado (catálogo público). La sesión se
> mantiene con la cookie `qva_session` y se restaura al reabrir la app.

---

## 🛠️ Stack técnico

| | |
|---|---|
| **Framework** | Flutter 3.47 · Dart 3.13 |
| **Estado** | Riverpod 3 (`Notifier`, `FutureProvider`) |
| **Navegación** | go_router 18 (`StatefulShellRoute` para la barra inferior) |
| **Red** | Dio 5 con interceptor de cookie de sesión |
| **Persistencia** | shared_preferences (sesión y preferencias) |
| **Plataforma** | Android (Kotlin) con `MethodChannel` propio para galería y enlaces |
| **Fuentes** | Bebas Neue · Inter · Roboto Mono (empaquetadas) |
| **CI/CD** | GitHub Actions → APK/AAB firmados + Google Play |

### Estructura del proyecto

```
lib/
├── app/                  # router y rutas
├── core/
│   ├── config/           # URL de la API, flags
│   ├── network/          # cliente Dio, endpoints por dominio
│   ├── theme/            # colores, tipografías, tema y assets por temporada
│   ├── platform/         # canal nativo (galería, enlaces)
│   ├── storage/          # sesión y preferencias
│   ├── theme/            # colores, tipografías, tema
│   └── widgets/          # logo, OTP
└── features/
    ├── auth/             # login, registro, verificación, perfil
    ├── catalog/          # modelos, API y proveedores del catálogo
    ├── home/             # home, pestañas, barra superior e inferior
    └── onboarding/       # pantalla de introducción
```

---

## 🤖 Automatización (CI/CD)

| Flujo | Qué hace |
|---|---|
| `push` a `main` | Analiza, prueba, compila el **AAB** (Play) y el **APK arm64 minificado y ofuscado** (26 MB) y actualiza la release **"latest"**. |
| `git tag v1.0.1` | Crea una release con versión y **sube el AAB a Google Play**. |
| Pull request | Solo valida (`analyze` + `test`), sin compilar APK ni publicar nada. |

Workflows: [`.github/workflows/android.yml`](.github/workflows/android.yml) y
[`.github/workflows/publish-play.yml`](.github/workflows/publish-play.yml).

**Secretos** que hay que crear en *Settings → Secrets and variables → Actions*:
`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` y
`PLAY_SERVICE_ACCOUNT_JSON`. Guía completa: [`doc/CI_CD.md`](doc/CI_CD.md).

---

## 📄 Documentación

| Documento | Contenido |
|---|---|
| [`doc/API_MAP.md`](doc/API_MAP.md) | Qué endpoint está conectado a qué pantalla, discrepancias con el `openapi.json` y lo que falta. |
| [`doc/CI_CD.md`](doc/CI_CD.md) | Creación del almacén de claves, secretos de GitHub, publicación en Google Play y verificación de firmas. |
| [`doc/TEMAS.md`](doc/TEMAS.md) | Cómo cambiar o añadir la temporada (logo, favicon e iconos). |
| [`doc/build_guide.md`](doc/build_guide.md) | Guía de compilación local: JDK 17, build debug y release optimizado para ARM64. |
| [`doc/QVATUBE_FLUTTER_DESIGN_SPEC.md`](doc/QVATUBE_FLUTTER_DESIGN_SPEC.md) | Sistema de diseño completo (colores, tipografías, iconos, componentes). |
| [`doc/openapi.json`](doc/openapi.json) | Especificación de la API de QvaTube. |

---

## 🗺️ Hoja de ruta

- [x] Autenticación completa (login, registro, recuperación y verificación por Telegram)
- [x] Catálogo por categorías con filtros, orden y paginación
- [x] Home con datos reales (recomendaciones, géneros, estadísticas, reseñas)
- [x] Perfil, plan, notificaciones, favoritos y comunidad
- [x] Barra inferior de 9 secciones con Inicio en el medio
- [x] CI/CD: APK firmado por push y publicación en Play Store por tag
- [ ] Reproductor de video, música y libros
- [ ] Descargas con autorización (`/api/download/authorize`)
- [ ] Progreso de reproducción y "marcar como visto"
- [ ] Canales de TV en vivo (hace falta un endpoint de canales)
- [ ] Temas descargables (nuevas temporadas desde el servidor)
- [ ] Notificaciones push y catálogo offline

---

## 📄 Licencia

MIT · Hecho con 🧡 para Cuba.
