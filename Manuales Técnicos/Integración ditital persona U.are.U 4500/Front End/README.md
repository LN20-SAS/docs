# Manual Técnico - Integración Digital Persona U.are.U 4500 (Front End)

## Descripción General

Este manual describe el proceso de integración del lector de huellas dactilares Digital Persona U.are.U 4500 en aplicaciones Angular utilizando las librerías oficiales de Digital Persona.

## Tabla de Contenidos

1. [Requisitos Previos](#requisitos-previos)
2. [Instalación y Configuración](#instalación-y-configuración)
3. [Uso del Cliente](#uso-del-cliente)
4. [API Reference](#api-reference)
5. [Eventos Disponibles](#eventos-disponibles)
6. [Ejemplos de Uso](#ejemplos-de-uso)
7. [Solución de Problemas](#solución-de-problemas)

---

## Requisitos Previos

- Node.js y npm instalados
- Proyecto Angular configurado
- Cliente HID Authentication Device instalado en el sistema operativo
- Dispositivo Digital Persona U.are.U 4500 conectado

---

## Instalación y Configuración

### Paso 1: Instalar Dependencias

Las librerías necesarias para la comunicación con el dispositivo biométrico son:

```bash
npm install @digitalpersona/fingerprint @digitalpersona/websdk
```

**Librerías instaladas:**
- `@digitalpersona/fingerprint`: SDK para la captura y manejo de huellas dactilares
- `@digitalpersona/websdk`: SDK web para la comunicación con el cliente HID

### Paso 2: Configurar angular.json

Las librerías de Digital Persona son módulos IIFE (Immediately Invoked Function Expression) y no módulos ESM válidos, por lo que deben cargarse de manera global.

Agregar las siguientes rutas en el archivo `angular.json`:

```json
{
  "projects": {
    "nombre-proyecto": {
      "architect": {
        "build": {
          "options": {
            "scripts": [
              "./node_modules/@digitalpersona/websdk/dist/websdk.client.ui.js",
              "./node_modules/@digitalpersona/fingerprint/dist/fingerprint.sdk.js"
            ]
          }
        }
      }
    }
  }
}
```

**Importante:** Esto permite que las librerías estén cargadas globalmente en el objeto `window` y sean accesibles desde cualquier parte de la aplicación.

### Paso 3: Configurar Referencias de TypeScript

Para que TypeScript reconozca las librerías cargadas globalmente, es necesario crear archivos de declaración de tipos.

#### 3.1. Crear la estructura de carpetas

Crear una carpeta `types` en la raíz del proyecto (al mismo nivel que `src`).

#### 3.2. Crear archivo fingerprint.d.ts

Crear el archivo `types/fingerprint.d.ts` con el siguiente contenido:

```typescript
/// <reference types="@digitalpersona/fingerprint" />
```

#### 3.3. Crear archivo websdk.d.ts

Crear el archivo `types/websdk.d.ts` con el siguiente contenido:

```typescript
/// <reference types="@digitalpersona/websdk" />
```

#### 3.4. Estructura final

```
proyecto/
├── src/
├── types/
│   ├── fingerprint.d.ts
│   └── websdk.d.ts
├── angular.json
├── package.json
└── tsconfig.json
```

**Resultado:** TypeScript ahora puede reconocer los tipos y funciones de ambas librerías en todo el proyecto.

---

## Uso del Cliente

### Inicialización del WebApi

Para comenzar a usar el lector de huellas, primero debemos obtener la instancia del WebApi desde el objeto global:

```typescript
// En tu componente o servicio
export class FingerprintService {
  private fingerprintApi: Fingerprint.WebApi;

  constructor() {
    // Acceder al namespace global Fingerprint
    this.fingerprintApi = new (window as any).Fingerprint.WebApi();
  }
}
```

**Nota Importante:** Al crear la instancia del WebApi, el cliente internamente:
- Crea una sesión de conexión con el dispositivo biométrico
- Guarda información de sesión en `sessionStorage` con las claves:
  - `"websdk"`
  - `"sessionId"`

### Declaración Global para TypeScript (Opcional)

Para mejor tipado, puedes declarar el namespace global en tu archivo de tipos:

```typescript
// types/global.d.ts
declare global {
  interface Window {
    Fingerprint: typeof Fingerprint;
    WebSdk: any;
  }
}

export {};
```

---

## API Reference

### Interfaces Principales

#### DeviceInfo
```typescript
interface DeviceInfo {
  DeviceID: string;              // ID único del dispositivo
  eUidType: DeviceUidType;       // Tipo de UID (Persistent o Volatile)
  eDeviceModality: DeviceModality; // Modalidad del dispositivo
  eDeviceTech: DeviceTechnology;  // Tecnología del sensor
}
```

#### WebApi - Métodos Principales

```typescript
class WebApi {
  // Enumerar dispositivos conectados
  enumerateDevices(): Promise<string[]>;
  
  // Obtener información del dispositivo
  getDeviceInfo(deviceUid: string): Promise<DeviceInfo>;
  
  // Iniciar captura de huellas
  startAcquisition(sampleFormat: SampleFormat, deviceUid?: string): Promise<void>;
  
  // Detener captura de huellas
  stopAcquisition(deviceUid?: string): Promise<void>;
  
  // Suscribirse a eventos
  on(event: string, handler: Handler<Event>): WebApi;
  
  // Desuscribirse de eventos
  off(event?: string, handler?: Handler<Event>): WebApi;
}
```

### Enumeraciones (Enums)

#### DeviceUidType
```typescript
enum DeviceUidType {
  Persistent = 0,  // UID persistente
  Volatile = 1     // UID temporal
}
```

#### DeviceModality
```typescript
enum DeviceModality {
  Unknown = 0,            // Desconocido
  Swipe = 1,              // Deslizamiento
  Area = 2,               // Área
  AreaMultifinger = 3     // Área multi-dedo
}
```

#### DeviceTechnology
```typescript
enum DeviceTechnology {
  Unknown = 0,       // Desconocido
  Optical = 1,       // Óptico
  Capacitive = 2,    // Capacitivo
  Thermal = 3,       // Térmico
  Pressure = 4       // Presión
}
```

#### SampleFormat
```typescript
enum SampleFormat {
  Raw = 1,           // Datos crudos
  Intermediate = 2,  // Formato intermedio
  Compressed = 3,    // Comprimido
  PngImage = 5       // Imagen PNG
}
```

#### QualityCode
```typescript
enum QualityCode {
  Good = 0,                 // Buena calidad
  NoImage = 1,              // Sin imagen
  TooLight = 2,             // Muy clara
  TooDark = 3,              // Muy oscura
  TooNoisy = 4,             // Mucho ruido
  LowContrast = 5,          // Bajo contraste
  NotEnoughFeatures = 6,    // Pocas características
  NotCentered = 7,          // No centrada
  NotAFinger = 8,           // No es un dedo
  TooHigh = 9,              // Muy arriba
  TooLow = 10,              // Muy abajo
  TooLeft = 11,             // Muy a la izquierda
  TooRight = 12,            // Muy a la derecha
  TooStrange = 13,          // Muy extraña
  TooFast = 14,             // Muy rápido
  TooSkewed = 15,           // Muy inclinada
  TooShort = 16,            // Muy corta
  TooSlow = 17,             // Muy lento
  ReverseMotion = 18,       // Movimiento inverso
  PressureTooHard = 19,     // Presión muy fuerte
  PressureTooLight = 20,    // Presión muy suave
  WetFinger = 21,           // Dedo húmedo
  FakeFinger = 22,          // Dedo falso
  TooSmall = 23,            // Muy pequeña
  RotatedTooMuch = 24       // Muy rotada
}
```

---

## Eventos Disponibles

El WebApi implementa un sistema de eventos para notificar sobre el estado del dispositivo y la captura de huellas.

### Lista de Eventos

| Evento | Descripción | Datos del Evento |
|--------|-------------|------------------|
| `DeviceConnected` | Dispositivo conectado | `deviceUid: string` |
| `DeviceDisconnected` | Dispositivo desconectado | `deviceUid: string` |
| `SamplesAcquired` | Muestras capturadas | `deviceUid, sampleFormat, samples` |
| `QualityReported` | Calidad de la muestra reportada | `deviceUid, quality: QualityCode` |
| `ErrorOccurred` | Error durante la captura | `deviceUid, error: number` |
| `AcquisitionStarted` | Captura iniciada | `deviceUid: string` |
| `AcquisitionStopped` | Captura detenida | `deviceUid: string` |
| `CommunicationFailed` | Fallo en la comunicación | - |

### Interfaces de Eventos

```typescript
// Evento de conexión
class DeviceConnected extends AcquisitionEvent {
  constructor(deviceUid: string);
}

// Evento de desconexión
class DeviceDisconnected extends AcquisitionEvent {
  constructor(deviceUid: string);
}

// Evento de muestras capturadas
class SamplesAcquired extends AcquisitionEvent {
  sampleFormat: SampleFormat;
  samples: string; // Datos de la huella en formato Base64
  constructor(deviceUid: string, sampleFormat: SampleFormat, samples: string);
}

// Evento de calidad
class QualityReported extends AcquisitionEvent {
  quality: QualityCode;
  constructor(deviceUid: string, quality: QualityCode);
}

// Evento de error
class ErrorOccurred extends AcquisitionEvent {
  error: number;
  constructor(deviceUid: string, error: number);
}
```

### Suscripción a Eventos

```typescript
// Método 1: Usando on()
fingerprintApi.on("SamplesAcquired", (event: Fingerprint.SamplesAcquired) => {
  console.log("Muestra capturada:", event.samples);
});

// Método 2: Usando propiedades
fingerprintApi.onSamplesAcquired = (event: Fingerprint.SamplesAcquired) => {
  console.log("Muestra capturada:", event.samples);
};
```

---

## Ejemplos de Uso

### Ejemplo 1: Servicio Básico de Huellas Dactilares

```typescript
import { Injectable } from '@angular/core';

@Injectable({
  providedIn: 'root'
})
export class FingerprintService {
  private fingerprintApi: any;
  private currentDeviceUid: string | null = null;

  constructor() {
    this.initializeApi();
  }

  private initializeApi(): void {
    try {
      // Acceder al namespace global
      const Fingerprint = (window as any).Fingerprint;
      this.fingerprintApi = new Fingerprint.WebApi();
      console.log('WebApi inicializado correctamente');
    } catch (error) {
      console.error('Error al inicializar WebApi:', error);
    }
  }

  async getDevices(): Promise<string[]> {
    try {
      const devices = await this.fingerprintApi.enumerateDevices();
      console.log('Dispositivos encontrados:', devices);
      return devices;
    } catch (error) {
      console.error('Error al enumerar dispositivos:', error);
      return [];
    }
  }

  async getDeviceInfo(deviceUid: string): Promise<any> {
    try {
      const info = await this.fingerprintApi.getDeviceInfo(deviceUid);
      console.log('Información del dispositivo:', info);
      return info;
    } catch (error) {
      console.error('Error al obtener información del dispositivo:', error);
      return null;
    }
  }

  async startCapture(deviceUid?: string): Promise<void> {
    try {
      const Fingerprint = (window as any).Fingerprint;
      const format = Fingerprint.SampleFormat.PngImage; // Capturar como imagen PNG
      
      await this.fingerprintApi.startAcquisition(format, deviceUid);
      this.currentDeviceUid = deviceUid || null;
      console.log('Captura iniciada');
    } catch (error) {
      console.error('Error al iniciar captura:', error);
      throw error;
    }
  }

  async stopCapture(deviceUid?: string): Promise<void> {
    try {
      await this.fingerprintApi.stopAcquisition(deviceUid);
      console.log('Captura detenida');
    } catch (error) {
      console.error('Error al detener captura:', error);
      throw error;
    }
  }

  onSamplesAcquired(callback: (samples: string) => void): void {
    this.fingerprintApi.on('SamplesAcquired', (event: any) => {
      callback(event.samples);
    });
  }

  onQualityReported(callback: (quality: number) => void): void {
    this.fingerprintApi.on('QualityReported', (event: any) => {
      callback(event.quality);
    });
  }

  onDeviceConnected(callback: (deviceUid: string) => void): void {
    this.fingerprintApi.on('DeviceConnected', (event: any) => {
      callback(event.deviceUid);
    });
  }

  onDeviceDisconnected(callback: (deviceUid: string) => void): void {
    this.fingerprintApi.on('DeviceDisconnected', (event: any) => {
      callback(event.deviceUid);
    });
  }

  onError(callback: (error: number) => void): void {
    this.fingerprintApi.on('ErrorOccurred', (event: any) => {
      callback(event.error);
    });
  }

  destroy(): void {
    // Limpiar suscripciones
    this.fingerprintApi.off();
  }
}
```

### Ejemplo 2: Componente de Captura de Huellas

```typescript
import { Component, OnInit, OnDestroy } from '@angular/core';
import { FingerprintService } from './fingerprint.service';

@Component({
  selector: 'app-fingerprint-capture',
  template: `
    <div class="fingerprint-container">
      <h2>Captura de Huella Dactilar</h2>
      
      <div class="device-info" *ngIf="deviceInfo">
        <p><strong>Dispositivo:</strong> {{ deviceInfo.DeviceID }}</p>
        <p><strong>Tecnología:</strong> {{ getTechnologyName(deviceInfo.eDeviceTech) }}</p>
      </div>

      <div class="status">
        <p>Estado: {{ status }}</p>
        <p *ngIf="quality !== null">Calidad: {{ getQualityMessage(quality) }}</p>
      </div>

      <div class="preview" *ngIf="fingerprintImage">
        <img [src]="fingerprintImage" alt="Huella capturada">
      </div>

      <div class="actions">
        <button (click)="initializeDevice()" [disabled]="isCapturing">
          Inicializar Dispositivo
        </button>
        <button (click)="startCapture()" [disabled]="!deviceReady || isCapturing">
          Iniciar Captura
        </button>
        <button (click)="stopCapture()" [disabled]="!isCapturing">
          Detener Captura
        </button>
      </div>
    </div>
  `,
  styles: [`
    .fingerprint-container {
      padding: 20px;
      max-width: 600px;
      margin: 0 auto;
    }

    .device-info, .status {
      background: #f5f5f5;
      padding: 15px;
      margin: 10px 0;
      border-radius: 5px;
    }

    .preview {
      margin: 20px 0;
      text-align: center;
    }

    .preview img {
      max-width: 300px;
      border: 2px solid #ddd;
      border-radius: 5px;
    }

    .actions {
      display: flex;
      gap: 10px;
      justify-content: center;
    }

    button {
      padding: 10px 20px;
      font-size: 14px;
      cursor: pointer;
      border: none;
      background: #007bff;
      color: white;
      border-radius: 5px;
    }

    button:disabled {
      background: #ccc;
      cursor: not-allowed;
    }

    button:hover:not(:disabled) {
      background: #0056b3;
    }
  `]
})
export class FingerprintCaptureComponent implements OnInit, OnDestroy {
  deviceInfo: any = null;
  deviceReady = false;
  isCapturing = false;
  status = 'No inicializado';
  quality: number | null = null;
  fingerprintImage: string | null = null;
  private deviceUid: string | null = null;

  constructor(private fingerprintService: FingerprintService) {}

  ngOnInit(): void {
    this.setupEventHandlers();
  }

  ngOnDestroy(): void {
    if (this.isCapturing) {
      this.stopCapture();
    }
    this.fingerprintService.destroy();
  }

  private setupEventHandlers(): void {
    // Evento: Muestra capturada
    this.fingerprintService.onSamplesAcquired((samples: string) => {
      console.log('Muestra capturada');
      // Convertir la muestra en imagen para visualización
      this.fingerprintImage = 'data:image/png;base64,' + samples;
    });

    // Evento: Calidad reportada
    this.fingerprintService.onQualityReported((quality: number) => {
      this.quality = quality;
      console.log('Calidad:', this.getQualityMessage(quality));
    });

    // Evento: Dispositivo conectado
    this.fingerprintService.onDeviceConnected((deviceUid: string) => {
      console.log('Dispositivo conectado:', deviceUid);
      this.status = 'Dispositivo conectado';
    });

    // Evento: Dispositivo desconectado
    this.fingerprintService.onDeviceDisconnected((deviceUid: string) => {
      console.log('Dispositivo desconectado:', deviceUid);
      this.status = 'Dispositivo desconectado';
      this.deviceReady = false;
    });

    // Evento: Error
    this.fingerprintService.onError((error: number) => {
      console.error('Error en captura:', error);
      this.status = `Error: ${error}`;
    });
  }

  async initializeDevice(): Promise<void> {
    try {
      this.status = 'Buscando dispositivos...';
      
      const devices = await this.fingerprintService.getDevices();
      
      if (devices.length === 0) {
        this.status = 'No se encontraron dispositivos';
        return;
      }

      this.deviceUid = devices[0];
      this.deviceInfo = await this.fingerprintService.getDeviceInfo(this.deviceUid);
      this.deviceReady = true;
      this.status = 'Dispositivo listo';
    } catch (error) {
      console.error('Error al inicializar:', error);
      this.status = 'Error al inicializar dispositivo';
    }
  }

  async startCapture(): Promise<void> {
    try {
      this.status = 'Iniciando captura...';
      await this.fingerprintService.startCapture(this.deviceUid || undefined);
      this.isCapturing = true;
      this.status = 'Coloque su dedo en el sensor';
      this.fingerprintImage = null;
      this.quality = null;
    } catch (error) {
      console.error('Error al iniciar captura:', error);
      this.status = 'Error al iniciar captura';
    }
  }

  async stopCapture(): Promise<void> {
    try {
      await this.fingerprintService.stopCapture(this.deviceUid || undefined);
      this.isCapturing = false;
      this.status = 'Captura detenida';
    } catch (error) {
      console.error('Error al detener captura:', error);
    }
  }

  getTechnologyName(tech: number): string {
    const technologies: { [key: number]: string } = {
      0: 'Desconocido',
      1: 'Óptico',
      2: 'Capacitivo',
      3: 'Térmico',
      4: 'Presión'
    };
    return technologies[tech] || 'Desconocido';
  }

  getQualityMessage(quality: number): string {
    const qualityMessages: { [key: number]: string } = {
      0: 'Buena calidad',
      1: 'Sin imagen',
      2: 'Muy clara',
      3: 'Muy oscura',
      4: 'Mucho ruido',
      5: 'Bajo contraste',
      6: 'Pocas características',
      7: 'No centrada',
      8: 'No es un dedo',
      9: 'Muy arriba',
      10: 'Muy abajo',
      11: 'Muy a la izquierda',
      12: 'Muy a la derecha',
      13: 'Muy extraña',
      14: 'Muy rápido',
      15: 'Muy inclinada',
      16: 'Muy corta',
      17: 'Muy lento',
      18: 'Movimiento inverso',
      19: 'Presión muy fuerte',
      20: 'Presión muy suave',
      21: 'Dedo húmedo',
      22: 'Dedo falso detectado',
      23: 'Muy pequeña',
      24: 'Muy rotada'
    };
    return qualityMessages[quality] || 'Calidad desconocida';
  }
}
```

### Ejemplo 3: Verificación de Huellas

```typescript
export class FingerprintVerificationService {
  constructor(private fingerprintService: FingerprintService) {}

  async captureAndVerify(storedFingerprint: string): Promise<boolean> {
    return new Promise((resolve, reject) => {
      let capturedSample: string;

      // Configurar evento de captura
      this.fingerprintService.onSamplesAcquired((samples: string) => {
        capturedSample = samples;
        
        // Aquí deberías usar un algoritmo de comparación de huellas
        // Este es solo un ejemplo simplificado
        const isMatch = this.compareFingerprints(storedFingerprint, capturedSample);
        
        this.fingerprintService.stopCapture();
        resolve(isMatch);
      });

      // Configurar evento de error
      this.fingerprintService.onError((error: number) => {
        this.fingerprintService.stopCapture();
        reject(new Error(`Error en captura: ${error}`));
      });

      // Iniciar captura
      this.fingerprintService.startCapture()
        .catch(error => reject(error));

      // Timeout de 30 segundos
      setTimeout(() => {
        this.fingerprintService.stopCapture();
        reject(new Error('Timeout: No se capturó ninguna huella'));
      }, 30000);
    });
  }

  private compareFingerprints(stored: string, captured: string): boolean {
    // NOTA: Esta es una comparación simplificada
    // En producción, deberías usar algoritmos específicos de comparación
    // proporcionados por Digital Persona u otros servicios de verificación
    return stored === captured;
  }
}
```

---

## Solución de Problemas

### Error: "Fingerprint is not defined"

**Causa:** Las librerías no están cargadas correctamente en el objeto global.

**Solución:**
1. Verificar que las rutas en `angular.json` sean correctas
2. Reiniciar el servidor de desarrollo (`ng serve`)
3. Limpiar caché del navegador

### Error: "Cannot find namespace 'Fingerprint'"

**Causa:** TypeScript no reconoce las declaraciones de tipos.

**Solución:**
1. Verificar que los archivos `.d.ts` estén creados en la carpeta `types`
2. Verificar que las referencias `/// <reference types="..." />` sean correctas
3. Reiniciar el editor de código

### El dispositivo no se detecta

**Causa:** El cliente HID no está instalado o no está en ejecución.

**Solución:**
1. Verificar que el cliente HID Authentication Device esté instalado
2. Verificar que el dispositivo esté conectado correctamente
3. Revisar el Administrador de dispositivos de Windows
4. Reiniciar el servicio del cliente HID

### Error de comunicación durante la captura

**Causa:** Pérdida de conexión con el dispositivo o el cliente HID.

**Solución:**
1. Reconectar el dispositivo
2. Reiniciar el cliente HID
3. Verificar que el puerto USB funcione correctamente
4. Limpiar el sessionStorage y reinicializar la conexión:
   ```typescript
   sessionStorage.removeItem('websdk');
   sessionStorage.removeItem('sessionId');
   ```

### Las muestras capturadas tienen baja calidad

**Causa:** Mala colocación del dedo o sensor sucio.

**Solución:**
1. Limpiar el sensor con un paño suave
2. Asegurar que el dedo esté limpio y seco
3. Presionar firmemente pero sin exceso
4. Centrar el dedo en el sensor

### Múltiples instancias de WebApi

**Problema:** Crear múltiples instancias puede causar conflictos.

**Solución:**
1. Usar un patrón Singleton para el servicio
2. Reutilizar la misma instancia de WebApi
3. Destruir correctamente las instancias anteriores antes de crear nuevas

---

## Mejores Prácticas

### 1. Gestión de Sesiones

```typescript
// Limpiar sesión anterior al iniciar
private clearPreviousSession(): void {
  sessionStorage.removeItem('websdk');
  sessionStorage.removeItem('sessionId');
}

// Verificar si existe una sesión activa
private hasActiveSession(): boolean {
  return sessionStorage.getItem('websdk') !== null;
}
```

### 2. Manejo de Errores

```typescript
async safeStartCapture(): Promise<void> {
  try {
    await this.startCapture();
  } catch (error) {
    console.error('Error al iniciar captura:', error);
    // Intentar recuperación
    await this.reinitializeDevice();
  }
}
```

### 3. Timeout en Capturas

```typescript
async captureWithTimeout(timeoutMs: number = 30000): Promise<string> {
  return Promise.race([
    this.captureFingerprint(),
    this.createTimeout(timeoutMs)
  ]);
}

private createTimeout(ms: number): Promise<never> {
  return new Promise((_, reject) => {
    setTimeout(() => reject(new Error('Timeout')), ms);
  });
}
```

### 4. Validación de Calidad

```typescript
async captureHighQualityFingerprint(): Promise<string> {
  return new Promise((resolve, reject) => {
    this.fingerprintService.onQualityReported((quality: number) => {
      if (quality === 0) { // Good quality
        this.fingerprintService.onSamplesAcquired((samples: string) => {
          resolve(samples);
        });
      } else {
        // Mostrar mensaje de retroalimentación al usuario
        this.showQualityFeedback(quality);
      }
    });
  });
}
```

### 5. Limpieza de Recursos

```typescript
ngOnDestroy(): void {
  // Detener captura si está activa
  if (this.isCapturing) {
    this.fingerprintService.stopCapture();
  }
  
  // Eliminar event listeners
  this.fingerprintService.destroy();
  
  // Limpiar referencias
  this.fingerprintImage = null;
  this.deviceInfo = null;
}
```

---

## Recursos Adicionales

- [Documentación oficial Digital Persona](https://www.digitalpersona.com/)
- [GitHub - @digitalpersona packages](https://github.com/hidglobal/digitalpersona-access-management-services)
- Manual de instalación del cliente HID ()

---

## Contacto y Soporte

Para soporte técnico o consultas adicionales, contactar al equipo de desarrollo.

**Última actualización:** Octubre 2025

