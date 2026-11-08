# -*- coding: utf-8 -*-
"""Blog en español, lote 8 (dispositivos Apple: widgets y Handoff). Ver blog_i18n.py."""

ES = {
    "widget-kidbox-schermata-home": {
        "title": "Los widgets de KidBox: el día de la familia en la pantalla de inicio",
        "desc": "Calendario, tareas, compra, tratamientos, fotos y plan de fitness en la pantalla de inicio del iPhone y del iPad, en tres tamaños. Se marca directamente desde el widget, sin abrir la app.",
        "body": """
Casi siempre que abres una app familiar quieres saber una sola cosa: qué hay hoy, qué falta por comprar, si ya se ha dado la dosis de la noche. Por eso KidBox tiene **widgets** para la pantalla de inicio del iPhone y del iPad: la respuesta está ahí cuando desbloqueas el móvil, y para las cosas pequeñas ni siquiera hace falta abrir la app.

![Los widgets de KidBox en la pantalla de inicio: tareas y calendario con los accesos directos](/assets/app/es/widgets.webp)

## Qué puede mostrar un widget

Cada widget muestra una sección, y la eliges manteniendo pulsado el widget y tocando «Editar widget»:

- **Calendario**: los planes de hoy y de los próximos días, con los colores de los eventos
- **Tareas**: las cosas pendientes, de una lista concreta si quieres; las que vencen antes van primero
- **Compra**: lo que falta por comprar
- **Tratamientos**: las dosis de hoy de una persona de la familia
- **Fotos**: un álbum familiar
- **Plan de fitness**: los entrenamientos de la persona que elijas

Puedes poner varios widgets uno al lado del otro, incluso de la misma sección: por ejemplo el calendario y, debajo, la compra.

## Tres tamaños

- **Pequeño**: el número y lo primero que hay que saber, por ejemplo cuántas tareas quedan
- **Mediano**: los primeros elementos completos, para leer de un vistazo
- **Grande**: la sección con más espacio y, debajo, **hasta seis accesos directos** a las secciones que elijas (tareas, compra, fotos, salud, chat, notas…). Abajo aparece la hora de la última actualización y el botón para actualizar al momento

## Se marca desde el widget

Los widgets no son solo para mirar. Con un toque en el círculo junto al elemento:

- una **tarea** queda hecha
- un producto de la **compra** queda comprado
- una **dosis** del tratamiento queda dada

El cambio llega a toda la familia como si lo hubieras hecho desde la app. En el súper, con el carro en una mano, es la forma más rápida de mantener al día la [lista de la compra](/es/tools/lista-della-spesa).

## Cómo se añade

1. Mantén pulsado un espacio vacío de la pantalla de inicio, toca **Editar** y luego **Añadir widget**
2. Busca **KidBox** y elige el tamaño
3. Mantén pulsado el widget nuevo, toca **Editar widget** y elige la sección (y, cuando haga falta, la lista, la persona o el álbum)

## Qué ven los demás

El widget muestra lo que ves tú en la app, nada más. Lo privado sigue siendo privado, y el contenido cifrado de la familia se queda en el dispositivo. El widget se actualiza solo cuando abres la app o cuando alguien cambia algo; el botón de abajo del grande sirve para cuando quieres estar seguro de tener la última versión.

## Un consejo

Poned el widget del calendario en la primera página del móvil de **los dos** padres. No hace falta acordarse de abrir la app: basta con desbloquear el móvil para ver que el jueves toca pediatra, y quién lleva al niño. Es el mismo principio de los [recordatorios que funcionan](/es/blog/promemoria-che-funzionano): la información llega adonde ya miras.

Los widgets están incluidos en todos los planes, en iPhone y iPad. Si también trabajas desde el Mac, lee cómo [seguir de un dispositivo a otro con Handoff](/es/blog/handoff-iphone-ipad-mac).
""",
    },
    "handoff-iphone-ipad-mac": {
        "title": "Handoff en KidBox: empiezas en el iPhone, terminas en el Mac",
        "desc": "La tarea, el evento o la visita que estás escribiendo pasa del iPhone al iPad o al Mac ya rellenada, en el punto en que estabas. Cómo funciona y qué lleva consigo.",
        "body": """
Pasa constantemente: empiezas a escribir algo en el móvil y te das cuenta de que sería más cómodo terminarlo en el ordenador. La reunión del colegio con la hora y la dirección, la visita al pediatra con el diagnóstico que copiar, la lista larga de la compra del sábado. Con **Handoff** en KidBox no empiezas de cero: abres la app en el otro dispositivo y encuentras lo que estabas haciendo, ya escrito.

## Qué pasa de un dispositivo a otro

**El sitio donde estás.** Si en el iPhone estás en el calendario, el Mac abre el calendario. También dentro de las secciones: la misma lista de tareas, el mismo álbum de fotos, la misma persona y la misma página en Salud (la ficha, las visitas, una visita concreta, las vacunas, los tratamientos).

**Lo que estás escribiendo.** Los borradores que llegan ya rellenados:

- una **tarea** o un producto de la **compra**, con la nota y la cantidad
- un **evento** del calendario, con fecha, hora y lugar
- un **mensaje** del chat familiar
- una **visita**, una **prueba** o un **tratamiento** en Salud, en el mismo paso de la ficha
- un **gasto**, con título, importe, fecha, categoría y notas
- la pregunta que le estás escribiendo al **asistente**

Si estás viendo algo que ya existe, como una nota o una tarea, el otro dispositivo abre justo eso.

## Cómo se usa

1. En el iPhone abre KidBox y empieza a escribir
2. En el **Mac** aparece el icono de KidBox en el Dock con el símbolo del teléfono; en el **iPad**, al final del Dock o en el selector de apps
3. Tócalo o haz clic: KidBox se abre allí, en el punto en que estabas

Funciona en todas las direcciones: del Mac al iPhone, del iPad al Mac, etc.

## Qué hace falta

- KidBox instalado en los dispositivos, con la misma familia
- la **misma cuenta de Apple** en todos, con Handoff activado (Ajustes › General › AirPlay y Continuidad en el iPhone, Ajustes del Sistema › General › AirDrop y Handoff en el Mac)
- los dispositivos cerca, con Bluetooth y wifi activados

Handoff es de Apple: funciona entre **tus** dispositivos, no entre los de dos personas. Para pasarle una tarea a tu pareja están las tareas asignadas y las [peticiones a la familia](/es/blog/chiedere-aiuto-in-famiglia).

## Qué no pasa, y por qué

- **Los adjuntos**: fotos y documentos se quedan en el dispositivo donde los añadiste. El texto llega, el archivo no
- **Contraseñas y Wallet**: son las secciones más delicadas, y se quedan fuera de Handoff a propósito
- **Los borradores viejos**: un borrador que no se retoma en un minuto se descarta, así no te encuentras por sorpresa un evento a medias de ayer

El borrador viaja directamente entre tus dispositivos con Handoff, **sin pasar por los servidores de KidBox**. Y si por error guardas la misma tarea o el mismo producto de la compra en los dos dispositivos, queda uno solo.

## Cuándo sirve de verdad

El caso típico es por la noche: alguien te escribe la hora de la función del colegio, empiezas el evento en el móvil desde el sofá y lo terminas en el Mac, donde copiar la dirección y las notas es más cómodo. O al revés: preparas la compra en el ordenador y, al salir, la encuentras en el móvil sin buscarla.

Handoff está incluido en todos los planes, entre iPhone, iPad y Mac. En la pantalla de inicio, en cambio, están [los widgets de KidBox](/es/blog/widget-kidbox-schermata-home).
""",
    },
}
