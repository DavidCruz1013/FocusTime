# FocusTime

FocusTime es una aplicación para iOS que ayuda a organizar sesiones de concentración, descansos, metas diarias y registro manual de aplicaciones.

Proyecto académico del Grupo #4 de la materia Normas y Estándares Internacionales, Facultad de Ciencias Aplicadas, Escuela de Informática, Universidad Tecnológica de El Salvador. Docente: José Orlando Girón Barrera.

## Enlaces

- Página del proyecto: https://focustime-grupo4.netlify.app
- Documento final (PDF): https://focustime-grupo4.netlify.app/documento-final.pdf
- Código fuente: https://github.com/DavidCruz1013/FocusTime

## Integrantes

- Argueta Ortiz Oscar Andrés (25-0389-2022)
- Ascencio Huezo Nidelson Ovidio (25-1670-2022)
- Cruz Ramírez David Salomón (25-0616-2022)
- Gómez Saravia Mauricio Enrique (25-2061-2022)
- Jiménez Ventura Georgina Lisseth (25-3274-2022)
- Rivas Guzmán Rodrigo Alonso (25-0964-2022)

## Funciones principales

- Sesiones de concentración con pausa, reanudación y finalización.
- Descansos opcionales y avisos locales.
- Metas diarias y progreso semanal.
- Registro manual de aplicaciones.

## Requisitos

- Mac con Xcode 15 o superior.
- iOS 17.0 o superior, en simulador o en un iPhone.

## Cómo ejecutar el proyecto

1. Descarga o clona este repositorio.
2. En la carpeta `Configuration`, copia `Signing.xcconfig.example` y renómbralo como `Signing.xcconfig`.
3. Abre `FocusTime.xcodeproj` en Xcode.
4. En Signing & Capabilities, elige tu equipo (Personal Team) y cambia el Bundle Identifier por uno único.
5. Elige un simulador o un iPhone conectado y presiona Cmd + R.

El archivo `Signing.xcconfig` contiene datos de firma personales, por eso no se incluye en el repositorio.

## Estructura del repositorio

- `FocusTime/`: código fuente en Swift y SwiftUI.
- `Tests/`: pruebas de reglas y persistencia.
- `Configuration/`: configuración de compilación.
- `web/`: página publicada en Netlify y documento final en PDF.

## Limitaciones

- FocusTime no puede silenciar las notificaciones de otras apps como WhatsApp o Instagram. Para eso se usa el modo Concentración de iOS.
- El control real de otras aplicaciones requiere la capacidad FamilyControls, que no forma parte de esta versión.
- Los datos se guardan solo en el dispositivo. No hay cuentas ni sincronización entre equipos.
