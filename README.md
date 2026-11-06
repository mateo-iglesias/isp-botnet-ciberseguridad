# Dos casos de botnet en clientes de un ISP: cómo encontré los equipos infectados

[Read in English](README.en.md) | [Leer en Español](README.md)

## Executive Summary

Two incidents at a fiber ISP (PPPoE customers on MikroTik) where residential
customers were generating malicious traffic. In both cases I used **Wireshark**
on the customer's LAN, **MikroTik Torch** on the PPPoE interface and the **ONU
web panel** to isolate devices one by one. **Case 1:** an unnamed Wi‑Fi IoT
device was acting as a **residential proxy** for a botnet (TCP to C2 servers on
ports 100–299); the obvious suspect, an Android TV box with a pirate IPTV app,
was not the culprit. **Case 2:** a **counterfeit "amazon IPTV" stick** with the
Xuper TV app was launching a **UDP carpet-bombing attack** (34 Mbps against a
whole /24) and changed its MAC address on every connection (112 different MACs),
so the ONU blacklist was useless; a **phone** in the same house kept the C2
channel open on TCP 9377. The repository includes both cases, a comparison and
MikroTik rules to block what was observed.

---

Proyecto personal basado en dos casos reales que atendí trabajando en un ISP
(internet por fibra con clientes PPPoE sobre MikroTik). Lo publico para que
alguien con un problema parecido pueda guiarse con lo que hice.

Los datos están anonimizados: no aparecen nombres, la empresa ni IPs reales de
clientes. Las únicas IPs reales son las de los servidores de la botnet.

## Herramientas

- **Wireshark**, en un portátil con Ubuntu conectado a la ONU del cliente.
- **Torch** de MikroTik, sobre la interfaz PPPoE del cliente.
- **Panel web de la ONU** (por HTTP), para ver los equipos conectados y usar la
  lista negra.
- **nmap**, para revisar puertos abiertos del equipo sospechoso.

## Los dos casos en una tabla

| | Caso 1 | Caso 2 |
|---|---|---|
| Qué se veía desde el MikroTik | Conexiones TCP constantes a servidores en puertos raros y ráfagas UDP | Ataque UDP de 34 Mbps contra una red completa (/24) |
| Equipo infectado | Aparato Wi‑Fi sin nombre | Stick clon "amazon IPTV" + un celular |
| App pirata en la casa | Tipo MagisTV en un TV Box | Xuper TV en el stick |
| Servidores de control | 43.x / 101.47.x, TCP 100–299 | Alibaba Cloud (47.252.x / 47.90.x), TCP 9377 |
| Comportamiento principal | Proxy residencial (sube lo mismo que baja) | Ataque DDoS por UDP (carpet bombing) |
| ¿Cambiaba de MAC? | No | Sí, 112 MACs distintas |
| ¿Sirvió la lista negra de la ONU? | Sí | No |
| ¿La ONU estaba infectada? | No | No (confirmado) |

---

## Caso 1: el culpable no era el TV Box

### El problema

Desde el MikroTik veíamos que un cliente residencial tenía tráfico que no era
normal para un hogar:

- Ráfagas de UDP que llegaban al tope de subida de su plan.
- Conexiones TCP constantes a un grupo de servidores, siempre en **puertos raros**
  (104, 129, 152, 184, 197…), uno distinto por servidor.

En la casa había un TV Box Android genérico, así que fue el primer sospechoso.

### Primera parte: visita al cliente

Conecté el portátil a un puerto LAN de la ONU y saqué dos capturas con
Wireshark, una con el TV Box apagado y otra encendido.

Lo que encontré:

- **El TV Box estaba conectado dos veces**: por cable (.8) y por Wi‑Fi (.9). Me
  di cuenta porque las dos IPs anunciaban el mismo ID de Chromecast en mDNS.
  Pensaba que eran dos equipos distintos.
- **Tenía ADB abierto en la red** (Android Debug Bridge). Lo anunciaba por mDNS
  como `adb-unidentified._adb._tcp.local`. Esa es una de las formas en que las
  botnets toman control de estos aparatos.
- **Tenía una app de IPTV pirata** (`com.android.msandroid`) con tráfico P2P.
- Había otro equipo Wi‑Fi **sin nombre** (.7), con un módulo Wi‑Fi de un
  fabricante chino, que llamaba la atención.

En una red con switch, desde el portátil no se ve el tráfico de los otros equipos
hacia internet. La captura sirvió para saber qué aparatos había y qué
anunciaban, no para ver el ataque.

### Segunda parte: aislar el equipo desde remoto

El resto lo hice desde la oficina: sacaba equipos de la red con la **lista negra
de la ONU** y revisaba en **Torch** si desaparecían las conexiones a los
servidores de la botnet.

Antes de empezar, Torch mostraba que casi toda la subida del cliente iba a esos
servidores, mientras que la bajada era navegación HTTPS normal. Ese patrón
(baja de internet y sube lo mismo a otro lado) es el de un **proxy residencial**:
alguien navega usando la conexión del cliente.

| Prueba | Resultado en Torch |
|---|---|
| TV Box apagado | Seguía el tráfico a la botnet |
| Lista negra al TV Box (Wi‑Fi y cable) y al .7 | Tráfico a la botnet en 0 |
| Habilito solo el .7 | Vuelve el tráfico a la botnet |
| TV Box conectado, .7 bloqueado | Solo tráfico normal y el P2P de la app pirata |
| .7 bloqueado de forma permanente | Limpio |

### Resultado

El equipo infectado **no era el TV Box**: era el aparato Wi‑Fi sin nombre (.7).
Quedó bloqueado en la ONU y el tráfico hacia la botnet bajó a cero. En la
revisión de toda la noche siguiente (casi 15 horas) no hubo ninguna conexión a
la botnet y el cliente bajaba 17 veces más de lo que subía, como cualquier hogar.

El TV Box quedó señalado como riesgo por la app pirata y el ADB abierto.

---

## Caso 2: un stick falsificado que cambiaba de MAC y un celular

### El problema

Otro cliente, días después. Este no hacía de proxy: **estaba atacando**. En el
momento del ataque, Torch mostraba:

- **34 Mbps de subida sostenidos** (unos 3.700 paquetes por segundo) y casi nada
  de bajada. En 44 segundos salieron 176 MB.
- Un **barrido UDP ("carpet bombing")**: paquetes hacia las 256 direcciones de
  una misma red /24, todos desde un solo puerto de origen hacia el mismo puerto
  de destino, y nadie respondía.
- Al mismo tiempo, el equipo abrió **119 conexiones en 40 segundos** a un
  servidor de Alibaba Cloud en el **puerto TCP 9377**. Es lo más probable que
  sea el servidor que le daba las órdenes.

Los servidores eran distintos a los del caso 1.

### La visita

Esta vez fui al sitio mientras un compañero en la oficina miraba Torch.

**1. La lista de equipos de la ONU.** Mientras capturaba con Wireshark, abrí en
el navegador la página de equipos conectados de la ONU. Como el panel va por HTTP
sin cifrar, la respuesta completa quedó en la captura. Ahí apareció lo raro:

- **112 registros con MAC `88:00:33:77:xx:xx`**: los primeros cuatro bytes
  iguales y solo cambiaban los dos últimos. Todos Android 13 y ninguno con nombre.
- Cada MAC nueva había pedido una IP nueva, así que el DHCP de la ONU ya iba
  repartiendo hasta la .137.
- El fabricante `88:00:33` no aparece registrado, y la MAC no tiene el bit que
  usan los celulares cuando la generan aleatoria. Los celulares de la casa sí
  tenían nombre y conservaban su MAC.

Era **un solo aparato que se inventaba una MAC nueva cada vez que se conectaba**.
Por eso la lista negra de la ONU no sirve con este equipo: lo bloqueas y vuelve
con otra MAC.

**2. UPnP.** Apenas se conectó, ese aparato envió una búsqueda SSDP
(`M-SEARCH upnp:rootdevice`) buscando un router con UPnP. Con UPnP un equipo
puede abrir puertos en el router sin pedirle permiso a nadie.

**3. nmap.** Los 100 puertos TCP más comunes estaban cerrados. Tiene sentido: el
equipo no espera conexiones, es él quien se conecta hacia afuera.

**4. El aparato.** En sus ajustes de red estaba la MAC `88:00:33:77:5b:89` y la IP
.137: era un **stick con la marca "amazon IPTV 5G"**. No es un Fire TV real, es un
clon con la marca falsificada. Tenía instalada la app pirata **Xuper TV**.

### Aislamiento en sitio

| Hora | Prueba | Resultado en Torch |
|---|---|---|
| 16:04 | Todo conectado | Ataque UDP de 34 Mbps + conexiones al puerto 9377 |
| 16:09 | Desconecto el stick | **El ataque para**, pero siguen las conexiones al 9377 (ahora a otros servidores de Alibaba) |
| 16:16 | Reseteo la ONU | — |
| 16:26 | Solo la ONU conectada, sin ningún equipo | **Silencio total**: la ONU está limpia |
| 16:34 | Reconecto todo menos el stick | Tráfico normal, pero **vuelve el 9377** |
| ~16:45 | Apago el Wi‑Fi de los celulares uno por uno | Al apagar el de la dueña, **el 9377 desaparece** |
| 16:51 | Medición final | 0,3 Mbps de subida contra 25 Mbps de bajada: normal |

### Resultado

Había **dos equipos involucrados**:

1. **El stick clon "amazon IPTV" con Xuper TV**: era el que lanzaba el ataque UDP.
   El ataque paró en cuanto lo desconecté.
2. **Un celular Samsung Galaxy A56** de la casa: mantenía abierto el canal hacia
   los servidores del puerto 9377. Tenía muchísimas apps instaladas, entre ellas
   un navegador poco conocido y unos 10 juegos.

No pude determinar qué app del celular era la responsable. Lo recomendado para la
dueña fue desinstalar lo que no use, pasar Google Play Protect y, si vuelve,
restablecerlo de fábrica.

### Lo que quedó abierto

- Con los dos equipos conectados al mismo tiempo no se puede separar si el stick
  también usaba el puerto 9377 o solo el celular.
- Quedaron unas pocas conexiones a un servidor de Tencent Cloud en el puerto
  8002, con poco tráfico. Puede ser una app legítima; lo dejé en observación.

---

## Prevención en MikroTik

Las reglas están en [`mikrotik.rsc`](mikrotik.rsc):

1. **Bloquear los servidores de la botnet** de los dos casos para toda la red.
   Si otro cliente intenta conectarse a esas IPs, la regla lo corta y queda en el
   log.
2. **Bloquear el patrón de puertos** para los clientes sospechosos: TCP 100–299
   (caso 1) y TCP 9377 (caso 2). Las IPs de los servidores cambiaron varias veces
   durante las pruebas, pero los puertos no.
3. **Limitar las conexiones UDP nuevas** de los clientes sospechosos, para frenar
   ataques como el del caso 2 sin dejarlos sin internet.

Un detalle útil: después de bloquear, en Torch aparecen conexiones con
**Tx > 0 y Rx = 0**. Es el equipo infectado intentando conectarse sin recibir
respuesta, o sea, la regla está funcionando.

## Lo que aprendí

- **El primer sospechoso no siempre es el culpable.** En el caso 1 el TV Box
  tenía todo para serlo, y era otro equipo.
- **Puede haber más de un equipo infectado en la misma casa.** En el caso 2 sacar
  el stick paró el ataque, pero el celular seguía conectado a la botnet.
- **Un aparato puede estar conectado por cable y por Wi‑Fi al mismo tiempo**, o
  **cambiar de MAC en cada conexión**. Antes de bloquear por MAC hay que revisar
  la lista de equipos de la ONU.
- **La lista negra de la ONU solo saca equipos del Wi‑Fi**, y no sirve contra un
  equipo que cambia de MAC. En ese caso hace falta lista blanca o retirar el
  aparato.
- **Para descartar la ONU, la prueba es dejarla sola.** Si con ningún equipo
  conectado la línea queda en silencio, la ONU está limpia.
- **El panel de la ONU por HTTP es un riesgo**: cualquiera que capture en esa red
  ve la lista de equipos y la clave del panel.
- **Una sola medición limpia no basta.** Estas botnets pueden pasar horas sin
  hacer nada. Conviene revisar otra vez a las 24 y 48 horas.

## Si te pasa algo parecido

1. Identifica en el MikroTik qué cliente genera el tráfico y mira con **Torch** a
   qué IPs y puertos se conecta.
2. En la casa, revisa con **Wireshark** qué equipos hay y qué anuncian (mDNS,
   SSDP). Busca ADB abierto, equipos que aparezcan dos veces y MACs que se repiten
   con pequeñas variaciones.
3. Deja la **ONU sola** y mide: si hay silencio, la infección está en un aparato.
4. Conecta o **saca los equipos uno por uno** (lista negra o apagando el Wi‑Fi del
   aparato) y mide con Torch después de cada cambio.
5. Cuando encuentres el equipo, retíralo o bloquéalo y aplica las reglas de
   `mikrotik.rsc`.
6. Desactiva UPnP en la ONU y revisa de nuevo a las 24 y 48 horas.

---

**Herramientas:** Wireshark · nmap · MikroTik RouterOS (Torch, firewall) · ONU GPON
