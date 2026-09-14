# -*- coding: utf-8 -*-
"""
Testi degli Strumenti in spagnolo e francese (vedi tools_data.py per il formato).

Alexa non c'è: la skill funziona solo in italiano, quindi la sua pagina e ogni
riferimento a lei restano fuori da ES e FR.
"""

ES = {
    "calendario": {
        "title": "Calendario familiar compartido",
        "short": "Los compromisos de todos en un solo calendario, con vista de mes, semana y día. Lo añada quien lo añada, el otro padre lo ve al instante.",
        "lead": "Un calendario donde caben visitas, entrenamientos, cumpleaños y reuniones del colegio — y que toda la familia ve actualizado, incluso con el móvil en el bolsillo.",
        "steps": [
            ("Añade un evento", "Título, día y hora; si quieres, a qué hijo se refiere y un recordatorio antes de que empiece."),
            ("Todos lo ven", "El evento aparece en el móvil del otro padre y en la web al mismo tiempo, sin invitaciones que aceptar."),
            ("Elige la vista", "Mes para el panorama, semana y día con cuadrícula horaria para ver dónde encajar lo siguiente."),
        ],
        "faq": [
            ("¿Hace falta que todos tengan el mismo móvil?", "No. KidBox funciona en iPhone, Android y web: cada uno usa lo que tiene, y el calendario es el mismo para todos."),
            ("¿Puedo recibir un recordatorio?", "Sí: para cada evento eliges con cuánta antelación avisarte, y la notificación llega a los dispositivos con las notificaciones activadas."),
            ("¿El asistente de IA puede crear eventos?", "Sí. Escribiendo «pon el pediatra el jueves a las 16» el asistente crea el evento en el calendario familiar."),
        ],
    },
    "to-do": {
        "title": "Listas de tareas para la familia",
        "short": "Listas compartidas, tareas asignadas a quien tiene que hacerlas y recordatorios en el momento justo.",
        "lead": "Las tareas de una familia no son de una sola persona: aquí se escriben una vez, se asignan y las marca quien las haya hecho.",
        "steps": [
            ("Crea una lista", "«Antes de las vacaciones», «Casa», «Colegio»: tantas como necesites, compartidas con la familia."),
            ("Asigna y recuerda", "Cada tarea puede tener un responsable y un recordatorio: la notificación llega a quien debe hacerla, cuando debe hacerla."),
            ("Márcala desde donde estés", "Desde el móvil o desde la web: la lista es la misma."),
        ],
        "faq": [
            ("¿Las listas son por hijo o por familia?", "Por familia: todos los miembros ven todas las listas. Aun así puedes indicar a qué hijo se refiere una tarea."),
            ("¿El recordatorio también le llega al otro padre?", "Le llega a quien tiene asignada la tarea. Si no está asignada a nadie, lo reciben todos."),
            ("¿Funciona sin conexión?", "Sí: las listas se pueden leer y editar, y se sincronizan en cuanto vuelve la red."),
        ],
    },
    "lista-della-spesa": {
        "title": "Lista de la compra compartida",
        "short": "Una sola lista para toda la familia, actualizada en tiempo real: ves quién añadió qué y tachas los productos mientras llenas el carro.",
        "lead": "Quien está en el supermercado ve lo que los demás añadieron hace un minuto. Se acabaron las fotos de la lista por WhatsApp.",
        "steps": [
            ("Añade desde cualquier sitio", "Desde el móvil o desde la web: el producto entra en la lista de la familia."),
            ("Mira quién y cuándo", "Cada línea dice quién la añadió y cuándo, así sabes si sigue siendo válida."),
            ("Tacha en el carro", "Lo que coges desaparece de la lista de todos, en tiempo real."),
        ],
        "faq": [
            ("¿Puedo tener más de una lista?", "Sí, por ejemplo supermercado y farmacia. Cada una se comparte con la familia."),
            ("¿La lista se actualiza aunque esté en otra app?", "Sí: al volver a KidBox ves los cambios de los demás, y las notificaciones te avisan de las novedades."),
            ("¿La compra acaba en Gastos?", "Puedes registrarla con un toque al final: importe, tienda y fecha van a los gastos de la familia."),
        ],
    },
    "note": {
        "title": "Notas familiares cifradas",
        "short": "Notas compartidas con el otro padre — el código del portal, lo que dijo la maestra — cifradas y siempre a mano.",
        "lead": "Las notas que se pasa una familia están llenas de cosas privadas. Aquí se cifran con una clave que solo existe en vuestros dispositivos.",
        "steps": [
            ("Escribe una nota", "Texto con formato, listas, enlaces. Desde el móvil o la web, con la misma nota abierta en ambos."),
            ("Compartida por defecto", "Cada nota es de la familia: el otro padre la encuentra enseguida, sin enviarla."),
            ("Cifrada de verdad", "El contenido viaja y se guarda cifrado; ni siquiera KidBox puede leerlo."),
        ],
        "faq": [
            ("¿Qué significa «cifrada»?", "La nota se cifra en tu dispositivo con la clave de la familia antes de salir. En los servidores solo hay texto ilegible."),
            ("¿Puedo adjuntar un archivo a una nota?", "Los archivos van en Documentos, cifrados igual; desde la nota puedes enlazarlos."),
            ("Si cambio de móvil, ¿conservo las notas?", "Sí: la clave de la familia se recupera al iniciar sesión y las notas vuelven a leerse."),
        ],
    },
    "spese": {
        "title": "Gastos familiares por categoría",
        "short": "Gastos de los hijos y de la casa, por categoría y por mes. Muchos aparecen solos: una visita, una revisión del coche, una factura.",
        "lead": "No es una app de contabilidad, sino la cuenta de lo que cuesta sacar adelante una familia — con gastos que llegan desde las otras secciones sin volver a escribirlos.",
        "steps": [
            ("Registra un gasto", "Importe, categoría, quién pagó, para qué hijo. Con una foto del ticket, si quieres."),
            ("Las otras secciones lo crean por ti", "Una visita médica, una reparación del coche, una factura de casa: al registrarlas allí, el gasto aparece aquí."),
            ("Mira el mes", "Totales por categoría y comparación con los meses anteriores, para ver adónde va el dinero."),
        ],
        "faq": [
            ("¿Puedo repartir un gasto entre los padres?", "Sí: cada gasto indica quién pagó, y el resumen muestra lo que ha adelantado cada uno."),
            ("¿Puedo exportar los datos?", "Sí, a un archivo que abren las hojas de cálculo."),
            ("¿Los gastos están cifrados?", "Los importes y las categorías son datos de la familia protegidos por el inicio de sesión; los adjuntos (tickets, recibos) se cifran como todos los documentos."),
        ],
    },
    "wallet": {
        "title": "Wallet: billetes, tarjetas de fidelidad y documentos",
        "short": "Billetes de tren y avión leídos del PDF por la IA, tarjetas de fidelidad con su código de barras y los documentos de identidad de los hijos. Compartido.",
        "lead": "La cartera que un padre querría que también tuviera el otro: la tarjeta del súper, la entrada de la excursión, la tarjeta sanitaria del niño.",
        "steps": [
            ("Importa un billete", "Sube el PDF: la IA lee fecha, hora, asientos y código, y te muestra un billete limpio para enseñar."),
            ("Añade las tarjetas de fidelidad", "Escanea el código de barras una vez: a partir de ahí lo muestra el móvil de cualquiera de la familia."),
            ("Documentos de identidad", "DNI, tarjeta sanitaria, pasaporte de los hijos: cifrados, con la fecha de caducidad a la vista."),
        ],
        "faq": [
            ("¿Leen el código de barras en caja?", "Sí: se vuelve a dibujar en pantalla en el mismo formato que el original."),
            ("¿Los documentos de identidad están seguros?", "Se cifran en el dispositivo antes de salir, como todos los documentos de KidBox."),
            ("¿Qué billetes reconoce la IA?", "Trenes, aviones, eventos y en general cualquier PDF con fechas, horas y códigos; si un campo no se lee, lo corriges a mano."),
        ],
    },
    "documenti": {
        "title": "Documentos familiares cifrados",
        "short": "Carpetas y categorías para los archivos de la familia — informes, contratos, notas del colegio — cifrados y accesibles desde las demás secciones.",
        "lead": "Un solo lugar para los archivos que necesitan ambos padres, con el cifrado que se espera para un informe médico o un contrato.",
        "steps": [
            ("Sube un archivo", "PDF, fotos, escaneos: desde el móvil, la web o compartiendo desde otra app."),
            ("Ordénalo en carpetas", "Carpetas y categorías a tu gusto; la búsqueda encuentra los archivos por nombre y por etiqueta."),
            ("Encuéntralo donde hace falta", "Un informe adjunto a una visita, un recibo a una reparación del coche: es el mismo archivo, visible desde ambas secciones."),
        ],
        "faq": [
            ("¿Cuánto espacio tengo?", "Depende del plan de la familia; el espacio se ve en Ajustes y lo comparten todos los miembros."),
            ("¿Puedo importar un documento y que lo lea la IA?", "Sí, con el plan Pro: a partir de una factura o un informe la IA propone el gasto, el evento o el vencimiento que crear."),
            ("¿Quién puede ver mis documentos?", "Solo los miembros de la familia. Los archivos se cifran con la clave de la familia, que los servidores no tienen."),
        ],
    },
    "password": {
        "title": "Contraseñas de la familia con autocompletado",
        "short": "El wifi, el portal del colegio, la cuenta del abuelo: credenciales familiares o personales, cifradas, con autocompletado y control de seguridad.",
        "lead": "Las contraseñas que necesitan dos personas no deben ir por chat. Aquí están cifradas, se rellenan solas y un control te dice cuáles son débiles o se han filtrado.",
        "steps": [
            ("Guarda una credencial", "Sitio, usuario, contraseña, notas. Elige si es de la familia o solo tuya: las personales no las ve nadie más."),
            ("Se rellena sola", "Con el autocompletado activado, en iPhone y Android la contraseña se introduce en el sitio o la app sin copiarla."),
            ("Revisa la seguridad", "El control señala contraseñas débiles, repetidas o filtradas, sin enviarlas nunca en claro."),
        ],
        "faq": [
            ("¿Cómo funciona el control de filtraciones?", "Con k-anonimato en Have I Been Pwned: solo se envía una parte del hash, nunca la contraseña."),
            ("¿Puedo generar contraseñas seguras?", "Sí, el generador crea contraseñas largas y aleatorias, con o sin símbolos."),
            ("¿Las contraseñas personales se cifran de otra forma?", "Sí: usan una clave derivada de tu identidad, así que ni siquiera los demás miembros de la familia pueden leerlas."),
        ],
    },
    "foto-e-video": {
        "title": "Álbumes familiares privados",
        "short": "Fotos y vídeos de los hijos en álbumes compartidos con el otro padre, cifrados y sincronizados — sin redes sociales ni la compresión del chat.",
        "lead": "Los momentos que importan están en un lugar solo vuestro: álbumes cifrados, sin algoritmos, sin la compresión del chat.",
        "steps": [
            ("Crea un álbum", "«Primer año», «Verano en la playa»: los álbumes son de la familia y los llenáis los dos."),
            ("Sube con calidad completa", "Las fotos y los vídeos se quedan como están, cifrados antes de salir del móvil."),
            ("Mirad juntos", "Galería por fecha, vistas previas rápidas y descarga del original cuando haga falta."),
        ],
        "faq": [
            ("¿Las fotos también están cifradas en los servidores?", "Sí: se cifran en el dispositivo con la clave de la familia. En los servidores solo hay archivos ilegibles."),
            ("¿Cuánto espacio ocupan?", "Cuentan en el espacio de la familia, que depende del plan; el resumen está en Ajustes."),
            ("¿Puedo compartir un álbum con los abuelos?", "Todavía no: los álbumes son visibles para los miembros de la familia. Eso sí, puedes invitar a un miembro más."),
        ],
    },
    "chat": {
        "title": "Chat familiar cifrado de extremo a extremo",
        "short": "Un chat solo para la familia, cifrado de extremo a extremo, con notas de voz transcritas y una galería con lo enviado. Sin grupos que gestionar.",
        "lead": "No es otro grupo de WhatsApp: es un chat dentro de la app donde ya están el calendario, los gastos y los documentos, y que nadie de fuera puede leer.",
        "steps": [
            ("Escribe o graba", "Mensajes, fotos, notas de voz. Las notas de voz se transcriben en el móvil, así puedes leerlas en una reunión."),
            ("Cifrado de extremo a extremo", "Los mensajes se cifran en tu dispositivo y se descifran en el del otro. Las notificaciones se descifran en el móvil."),
            ("Encuentra lo enviado", "Las fotos y los archivos enviados están en la galería del chat, sin desplazarte sin fin."),
        ],
        "faq": [
            ("¿Quién está en el chat?", "Todos los miembros de la familia, y nadie más. No hay grupos que crear."),
            ("¿Puedo desactivarlo?", "Sí, desde Ajustes. Los demás siguen escribiéndose y recuperas los mensajes al volver a activarlo."),
            ("¿El chat funciona en la web?", "Sí, con los mismos mensajes y el mismo cifrado que en el móvil."),
        ],
    },
    "salute": {
        "title": "Salud de los hijos: visitas, vacunas e historial médico",
        "short": "El historial clínico de cada miembro — visitas, análisis, vacunas, tratamientos — con los informes adjuntos y un resumen para el médico. Con Apple Health y Health Connect.",
        "lead": "Cuando el pediatra pregunta «¿cuándo fue el último refuerzo?», la respuesta está aquí, con el informe al lado. Y los datos del móvil — pasos, frecuencia cardíaca, entrenamientos — entran solos.",
        "steps": [
            ("Registra visitas y análisis", "Fecha, médico, resultado, informe adjunto. Una visita con coste se convierte también en un gasto."),
            ("Ten las vacunas al día", "La cartilla de vacunación de cada hijo, con los refuerzos en el calendario."),
            ("Enseña el historial médico", "Un documento resumen, actualizado, para abrir en la consulta o enviar a un médico nuevo."),
        ],
        "faq": [
            ("¿Los datos de salud están cifrados?", "Sí: los informes y adjuntos se cifran con la clave de la familia, y las fichas clínicas solo las pueden leer los miembros."),
            ("¿Qué llega de Apple Health / Health Connect?", "Pasos, frecuencia cardíaca, tensión arterial, SpO₂, calorías activas, entrenamientos y distancia, solo si das permiso."),
            ("¿Qué añade el plan Pro?", "Planes de alimentación y de ejercicio generados por IA a medida del perfil, y un análisis mensual del historial de salud."),
        ],
    },
    "casa": {
        "title": "Hogar: garantías, mantenimiento y vencimientos",
        "short": "Electrodomésticos con garantía y mantenimiento, y los vencimientos de la casa — facturas, impuestos, contratos — con recordatorios y recibos.",
        "lead": "La caldera, la lavadora, el seguro del hogar, la tasa de basuras: cosas que vencen y que normalmente recuerda un solo padre. Aquí se las recuerdan a los dos.",
        "steps": [
            ("Registra tus bienes", "Marca, modelo, fecha de compra, garantía, manual en PDF. El vencimiento de la garantía va al calendario."),
            ("Registra el mantenimiento", "Revisión de la caldera, filtros, aire acondicionado: cuándo se hizo y cuándo toca."),
            ("Vencimientos y pagos", "Facturas, impuestos y contratos con importe, recordatorio y recibo adjunto; una vez pagados, se convierten en gastos."),
        ],
        "faq": [
            ("¿Los vencimientos avisan a todos?", "Sí, el recordatorio llega a los miembros de la familia con las notificaciones activadas."),
            ("¿Puedo adjuntar el recibo?", "Sí: va a Documentos, cifrado, vinculado al vencimiento."),
            ("¿En qué se diferencia de Vehículos?", "Vehículos tiene los vencimientos propios del coche — impuesto de circulación, seguro, inspección técnica — y las intervenciones del taller."),
        ],
    },
    "veicoli": {
        "title": "Vehículos: impuesto, seguro e inspección técnica",
        "short": "Una ficha para cada coche con los vencimientos que importan — impuesto de circulación, seguro, inspección técnica — y las intervenciones del taller con coste y recibo.",
        "lead": "Los coches de la familia tienen vencimientos que salen caros si se olvidan. Aquí están en una sola ficha, con el historial de intervenciones y lo que costaron.",
        "steps": [
            ("Añade el vehículo", "Matrícula, modelo, kilómetros. Los vencimientos de impuesto, seguro e inspección van al calendario con sus recordatorios."),
            ("Registra las intervenciones", "Revisión, neumáticos, pastillas de freno, reparaciones: fecha, kilómetros, coste y recibo adjunto."),
            ("Mira cuánto cuesta", "Cada intervención con coste es también un gasto de la familia, en la categoría correcta."),
        ],
        "faq": [
            ("¿El impuesto de circulación es una intervención?", "No, es un vencimiento de la ficha del vehículo: lo registras una vez y se repite cada año."),
            ("¿Puedo tener varios vehículos?", "Sí, una ficha para cada uno, visible para toda la familia."),
            ("¿Dónde van los recibos?", "A Documentos, cifrados, vinculados a la intervención."),
        ],
    },
    "animali": {
        "title": "Mascotas: vacunas y veterinario",
        "short": "El perfil de cada mascota con visitas al veterinario, vacunas, antiparasitarios y documentos — cartilla y microchip — adjuntos.",
        "lead": "El perro y el gato tienen su cartilla como los niños, y las mismas cosas que recordar: el refuerzo, el antipulgas, la revisión anual.",
        "steps": [
            ("Crea el perfil", "Nombre, especie, raza, fecha de nacimiento, microchip, foto."),
            ("Registra los eventos", "Vacunas, visitas, tratamientos, con la fecha del próximo y un recordatorio."),
            ("Adjunta los documentos", "Cartilla sanitaria, pasaporte, certificados: en Documentos, cifrados."),
        ],
        "faq": [
            ("¿Hay recordatorios para los refuerzos?", "Sí, para cada evento puedes fijar la fecha del próximo y recibir el aviso."),
            ("¿Los gastos del veterinario van a Gastos?", "Sí, si indicas un coste el evento se convierte también en un gasto."),
            ("¿Cuántas mascotas puedo añadir?", "Todas las que tengáis."),
        ],
    },
    "posizione": {
        "title": "Ubicación familiar y zonas",
        "short": "Dónde está cada uno en un mapa, con avisos cuando alguien llega o sale de un lugar, y ubicación temporal para una tarde.",
        "lead": "No es un rastreador: es una ubicación que cada uno activa y desactiva, con los avisos que de verdad sirven — «ha llegado al colegio», «ha salido del trabajo».",
        "steps": [
            ("Comparte cuando quieras", "Cada uno decide si compartir, de forma continua o durante un tiempo limitado."),
            ("Crea un lugar", "Casa, colegio, abuelos: una zona alrededor del sitio, con aviso al llegar y al salir."),
            ("Mira el mapa", "Todos los miembros que comparten, con la última actualización y la batería."),
        ],
        "faq": [
            ("¿Puedo dejar de compartir?", "Sí, en cualquier momento, y los demás reciben un aviso de que has dejado de compartir."),
            ("¿La ubicación está cifrada?", "Las coordenadas en tiempo real solo las pueden leer los miembros de la familia y no se guardan como historial."),
            ("¿Gasta mucha batería?", "Usa las actualizaciones en segundo plano del sistema, optimizadas para el consumo."),
        ],
    },
    "viaggi": {
        "title": "Viajes en familia con itinerario de IA",
        "short": "Un itinerario día a día generado por IA para tu familia, con lugares de Google en el mapa, «Historia y territorio», y las fotos, gastos y tareas del viaje.",
        "lead": "Di adónde vais, con quién y cuánto tiempo: la IA propone un itinerario pensado para niños con lugares reales en el mapa. Después, el viaje reúne todo lo demás.",
        "steps": [
            ("Describe el viaje", "Destino, fechas, edad de los hijos, ritmo. La IA organiza qué hacer día a día."),
            ("Explora el mapa", "Restaurantes, parques y museos de Google, con horarios y valoraciones; «Historia y territorio» cuenta la historia del lugar."),
            ("Vive el viaje", "Fotos, gastos, tareas y notas del viaje se quedan en su ficha, compartida con la familia."),
        ],
        "faq": [
            ("¿Se puede modificar el itinerario?", "Sí: mueves, quitas y añades paradas; la IA es un punto de partida."),
            ("¿Hace falta el plan Pro?", "Sí, la generación del itinerario y los contenidos de IA requieren Pro o Max."),
            ("¿Dónde van los billetes?", "En el Wallet, leídos del PDF; desde el viaje llegas a ellos con un toque."),
        ],
    },
    "assistente-ai": {
        "title": "Asistente de IA de la familia",
        "short": "Un asistente que conoce el calendario, los gastos, la salud y los documentos de la familia, y actúa: crea eventos, tareas y gastos, y lee los documentos que importas.",
        "lead": "No es un chat genérico: es un asistente con el contexto de tu familia, que a «¿cuándo le pusieron la antitetánica?» responde con la fecha, y convierte «apunta 40 € del dentista» en un gasto.",
        "steps": [
            ("Pregunta", "Con lenguaje natural, desde el móvil o la web. El asistente responde con vuestros datos, no con los de internet."),
            ("Deja que actúe", "Eventos, tareas, gastos: los crea por ti y te los muestra antes de guardarlos."),
            ("Importa un documento", "Una factura o un informe: la IA lo lee y propone qué registrar — gasto, vencimiento, visita."),
        ],
        "faq": [
            ("¿Qué datos ve la IA?", "Solo los que eliges compartir, petición a petición; para el contexto de Salud puedes elegir un resumen o que te pregunte cada vez."),
            ("¿Está incluido en el plan Free?", "El plan Free tiene 5 mensajes de prueba, una sola vez; el uso continuado requiere Pro o Max."),
            ("¿Qué es la «mente proactiva»?", "Con Pro, el asistente prepara por su cuenta un resumen por la mañana, un repaso semanal y un análisis mensual."),
        ],
    },
    "famiglia": {
        "title": "Familia, perfiles e invitaciones",
        "short": "Un perfil para cada padre y cada hijo, una invitación por enlace o QR que lleva la clave de cifrado, y varias familias para quien las necesite.",
        "lead": "Todo en KidBox es «de la familia»: la familia se crea en un minuto, el otro padre entra con un enlace y desde entonces veis las mismas cosas.",
        "steps": [
            ("Crea la familia", "Nombre, primer hijo, tu nombre: el asistente de configuración hace el resto y genera la clave de cifrado."),
            ("Invita a tu pareja", "Un enlace para enviar o un QR para escanear, válidos 24 horas y una sola vez: dentro va la clave, protegida."),
            ("Añade a los hijos", "Un perfil para cada uno, con fecha de nacimiento y foto; las fichas de salud y del colegio se vinculan al perfil."),
        ],
        "faq": [
            ("¿Puedo estar en dos familias?", "Sí, por ejemplo una familia reconstituida y los abuelos: cambias de una a otra desde Ajustes."),
            ("¿Y si pierdo el móvil?", "Inicia sesión desde otro dispositivo: la clave de la familia se recupera desde la cuenta y los datos vuelven a leerse."),
            ("¿Cuántas personas pueden entrar?", "Depende del plan; el Free cubre una familia de dos padres."),
        ],
    },
}

FR = {
    "calendario": {
        "title": "Calendrier familial partagé",
        "short": "Les engagements de chacun dans un seul calendrier, en vue mois, semaine et jour. Peu importe qui ajoute l'événement, l'autre parent le voit tout de suite.",
        "lead": "Un calendrier où trouvent place rendez-vous médicaux, entraînements, anniversaires et réunions de classe — et que toute la famille voit à jour, même le téléphone dans la poche.",
        "steps": [
            ("Ajoutez un événement", "Titre, jour et heure ; si vous voulez, l'enfant concerné et un rappel avant le début."),
            ("Tout le monde le voit", "L'événement apparaît sur le téléphone de l'autre parent et sur le web au même moment, sans invitation à accepter."),
            ("Choisissez la vue", "Mois pour la vue d'ensemble, semaine et jour avec une grille horaire pour voir où caser la suite."),
        ],
        "faq": [
            ("Tout le monde doit-il avoir le même téléphone ?", "Non. KidBox fonctionne sur iPhone, Android et le web : chacun utilise ce qu'il a, et le calendrier est le même pour tous."),
            ("Puis-je recevoir un rappel ?", "Oui : pour chaque événement, vous choisissez quand être prévenu, et la notification arrive sur les appareils où les notifications sont activées."),
            ("L'assistant IA peut-il créer des événements ?", "Oui. En écrivant « mets le pédiatre jeudi à 16h », l'assistant crée l'événement dans le calendrier familial."),
        ],
    },
    "to-do": {
        "title": "Listes de tâches pour la famille",
        "short": "Des listes partagées, des tâches attribuées à ceux qui doivent les faire et des rappels au bon moment.",
        "lead": "Les tâches d'une famille n'appartiennent pas à une seule personne : ici, on les écrit une fois, on les attribue et celui qui les a faites les coche.",
        "steps": [
            ("Créez une liste", "« Avant les vacances », « Maison », « École » : autant qu'il en faut, partagées avec la famille."),
            ("Attribuez et rappelez", "Chaque tâche peut avoir un responsable et un rappel : la notification arrive à la personne concernée, au moment voulu."),
            ("Cochez où que vous soyez", "Depuis le téléphone ou le web : c'est la même liste."),
        ],
        "faq": [
            ("Les listes sont-elles par enfant ou par famille ?", "Par famille : chaque membre voit toutes les listes. Vous pouvez quand même indiquer l'enfant concerné par une tâche."),
            ("Le rappel arrive-t-il aussi à l'autre parent ?", "Il arrive à la personne à qui la tâche est attribuée. Si elle n'est attribuée à personne, tout le monde le reçoit."),
            ("Ça marche hors connexion ?", "Oui : les listes restent lisibles et modifiables, et se synchronisent dès que le réseau revient."),
        ],
    },
    "lista-della-spesa": {
        "title": "Liste de courses partagée",
        "short": "Une seule liste pour toute la famille, mise à jour en temps réel : on voit qui a ajouté quoi, et on coche en remplissant le chariot.",
        "lead": "Celui qui est au supermarché voit ce que les autres ont ajouté il y a une minute. Fini les photos de la liste sur WhatsApp.",
        "steps": [
            ("Ajoutez de n'importe où", "Depuis le téléphone ou le web : l'article arrive dans la liste de la famille."),
            ("Voyez qui et quand", "Chaque ligne indique qui l'a ajoutée et quand, pour savoir si elle est toujours valable."),
            ("Cochez au chariot", "Les articles pris disparaissent de la liste de tous, en temps réel."),
        ],
        "faq": [
            ("Puis-je avoir plusieurs listes ?", "Oui, par exemple supermarché et pharmacie. Chacune est partagée avec la famille."),
            ("La liste se met-elle à jour pendant que j'utilise une autre app ?", "Oui : en revenant dans KidBox, vous voyez les modifications des autres, et les notifications vous signalent les nouveautés."),
            ("Les courses finissent-elles dans les Dépenses ?", "Vous pouvez les enregistrer d'un toucher à la fin : montant, magasin et date vont dans les dépenses de la famille."),
        ],
    },
    "note": {
        "title": "Notes familiales chiffrées",
        "short": "Des notes partagées avec l'autre parent — le code du portail, ce qu'a dit la maîtresse — chiffrées et toujours à portée de main.",
        "lead": "Les notes qu'une famille s'échange sont pleines de choses privées. Ici, elles sont chiffrées avec une clé qui n'existe que sur vos appareils.",
        "steps": [
            ("Écrivez une note", "Texte mis en forme, listes, liens. Depuis le téléphone ou le web, avec la même note ouverte des deux côtés."),
            ("Partagée par défaut", "Chaque note appartient à la famille : l'autre parent la trouve tout de suite, sans l'envoyer."),
            ("Vraiment chiffrée", "Le contenu circule et est stocké chiffré ; même KidBox ne peut pas le lire."),
        ],
        "faq": [
            ("Que veut dire « chiffrée » ?", "La note est chiffrée sur votre appareil avec la clé de la famille avant de partir. Les serveurs ne contiennent que du texte illisible."),
            ("Puis-je joindre un fichier à une note ?", "Les fichiers vont dans Documents, chiffrés de la même façon ; vous pouvez les lier depuis la note."),
            ("Si je change de téléphone, je garde mes notes ?", "Oui : la clé de la famille se récupère à la connexion et les notes redeviennent lisibles."),
        ],
    },
    "spese": {
        "title": "Dépenses familiales par catégorie",
        "short": "Les dépenses des enfants et de la maison, par catégorie et par mois. Beaucoup apparaissent toutes seules : une consultation, un entretien de voiture, une facture.",
        "lead": "Pas une app de comptabilité, mais le compte de ce que coûte une famille — avec des dépenses qui arrivent des autres rubriques sans les ressaisir.",
        "steps": [
            ("Enregistrez une dépense", "Montant, catégorie, qui a payé, pour quel enfant. Avec une photo du ticket, si vous voulez."),
            ("Les autres rubriques les créent pour vous", "Une consultation médicale, une réparation de voiture, une facture de la maison : quand vous les enregistrez là-bas, la dépense apparaît ici."),
            ("Regardez le mois", "Totaux par catégorie et comparaison avec les mois précédents, pour voir où va l'argent."),
        ],
        "faq": [
            ("Puis-je répartir une dépense entre les parents ?", "Oui : chaque dépense indique qui a payé, et le récapitulatif montre ce que chacun a avancé."),
            ("Puis-je exporter les données ?", "Oui, dans un fichier lisible par les tableurs."),
            ("Les dépenses sont-elles chiffrées ?", "Les montants et catégories sont des données de la famille protégées par la connexion ; les pièces jointes (tickets, reçus) sont chiffrées comme tous les documents."),
        ],
    },
    "wallet": {
        "title": "Wallet : billets, cartes de fidélité et papiers",
        "short": "Billets de train et d'avion lus depuis le PDF par l'IA, cartes de fidélité avec leur code-barres, pièces d'identité des enfants. Partagé.",
        "lead": "Le portefeuille qu'un parent aimerait que l'autre ait aussi : la carte du supermarché, le billet de la sortie scolaire, la carte vitale de l'enfant.",
        "steps": [
            ("Importez un billet", "Chargez le PDF : l'IA lit la date, l'heure, les places et le code, et vous montre un billet net à présenter."),
            ("Ajoutez les cartes de fidélité", "Scannez le code-barres une fois : ensuite, le téléphone de n'importe qui dans la famille peut l'afficher."),
            ("Pièces d'identité", "Carte d'identité, carte de santé, passeport des enfants : chiffrés, avec la date d'expiration bien visible."),
        ],
        "faq": [
            ("Le code-barres passe-t-il en caisse ?", "Oui : il est redessiné à l'écran dans le même format que l'original."),
            ("Les pièces d'identité sont-elles en sécurité ?", "Elles sont chiffrées sur l'appareil avant de partir, comme tous les documents de KidBox."),
            ("Quels billets l'IA reconnaît-elle ?", "Trains, avions, événements et en général tout PDF avec des dates, des heures et des codes ; si un champ n'est pas lu, vous le corrigez à la main."),
        ],
    },
    "documenti": {
        "title": "Documents familiaux chiffrés",
        "short": "Dossiers et catégories pour les fichiers de la famille — comptes rendus, contrats, bulletins — chiffrés et accessibles depuis toutes les autres rubriques.",
        "lead": "Un seul endroit pour les fichiers dont les deux parents ont besoin, avec le chiffrement qu'on attend pour un compte rendu médical ou un contrat.",
        "steps": [
            ("Importez un fichier", "PDF, photos, numérisations : depuis le téléphone, le web ou en partageant depuis une autre app."),
            ("Rangez en dossiers", "Dossiers et catégories à votre guise ; la recherche trouve les fichiers par nom et par étiquette."),
            ("Retrouvez-le là où il sert", "Un compte rendu joint à une consultation, un reçu à une réparation : c'est le même fichier, visible depuis les deux rubriques."),
        ],
        "faq": [
            ("Combien d'espace ai-je ?", "Cela dépend de l'offre de la famille ; l'espace s'affiche dans Réglages et il est partagé par tous les membres."),
            ("Puis-je importer un document et le faire lire par l'IA ?", "Oui, avec l'offre Pro : à partir d'une facture ou d'un compte rendu, l'IA propose la dépense, l'événement ou l'échéance à créer."),
            ("Qui peut voir mes documents ?", "Uniquement les membres de la famille. Les fichiers sont chiffrés avec la clé de la famille, que les serveurs n'ont pas."),
        ],
    },
    "password": {
        "title": "Mots de passe de la famille avec remplissage automatique",
        "short": "Le wifi, le portail de l'école, le compte de papi : identifiants familiaux ou personnels, chiffrés, avec remplissage automatique et contrôle de sécurité.",
        "lead": "Les mots de passe dont deux personnes ont besoin n'ont rien à faire dans un chat. Ici, ils sont chiffrés, se remplissent tout seuls, et un contrôle indique ceux qui sont faibles ou ont fuité.",
        "steps": [
            ("Enregistrez un identifiant", "Site, nom d'utilisateur, mot de passe, notes. Choisissez s'il est familial ou rien qu'à vous : les personnels, personne d'autre ne les voit."),
            ("Il se remplit tout seul", "Avec le remplissage automatique activé, sur iPhone et Android le mot de passe s'insère dans le site ou l'app sans le copier."),
            ("Vérifiez la sécurité", "Le contrôle signale les mots de passe faibles, réutilisés ou compromis, sans jamais les envoyer en clair."),
        ],
        "faq": [
            ("Comment fonctionne le contrôle des fuites ?", "Avec le k-anonymat sur Have I Been Pwned : seule une partie du hash est envoyée, jamais le mot de passe."),
            ("Puis-je générer des mots de passe sûrs ?", "Oui, le générateur crée des mots de passe longs et aléatoires, avec ou sans symboles."),
            ("Les mots de passe personnels sont-ils chiffrés autrement ?", "Oui : ils utilisent une clé dérivée de votre identité, si bien que même les autres membres de la famille ne peuvent pas les lire."),
        ],
    },
    "foto-e-video": {
        "title": "Albums de famille privés",
        "short": "Photos et vidéos des enfants dans des albums partagés avec l'autre parent, chiffrés et synchronisés — sans réseaux sociaux ni compression de chat.",
        "lead": "Les moments qui comptent sont dans un endroit rien qu'à vous : albums chiffrés, sans algorithme, sans compression de chat.",
        "steps": [
            ("Créez un album", "« Première année », « Été à la mer » : les albums appartiennent à la famille et vous les remplissez à deux."),
            ("Importez en pleine qualité", "Photos et vidéos restent intactes, chiffrées avant de quitter le téléphone."),
            ("Regardez ensemble", "Galerie par date, aperçus rapides, téléchargement de l'original si besoin."),
        ],
        "faq": [
            ("Les photos sont-elles aussi chiffrées sur les serveurs ?", "Oui : elles sont chiffrées sur l'appareil avec la clé de la famille. Les serveurs ne contiennent que des fichiers illisibles."),
            ("Combien d'espace occupent-elles ?", "Elles comptent dans l'espace de la famille, qui dépend de l'offre ; le récapitulatif est dans Réglages."),
            ("Puis-je partager un album avec les grands-parents ?", "Pas encore : les albums sont visibles par les membres de la famille. Vous pouvez en revanche inviter un membre de plus."),
        ],
    },
    "chat": {
        "title": "Chat familial chiffré de bout en bout",
        "short": "Un chat réservé à la famille, chiffré de bout en bout, avec messages vocaux transcrits et galerie des médias envoyés. Aucun groupe à gérer.",
        "lead": "Pas un énième groupe WhatsApp : un chat dans l'app où se trouvent déjà le calendrier, les dépenses et les documents, et que personne d'extérieur ne peut lire.",
        "steps": [
            ("Écrivez ou enregistrez", "Messages, photos, vocaux. Les vocaux sont transcrits sur le téléphone, pour les lire même en réunion."),
            ("Chiffré de bout en bout", "Les messages sont chiffrés sur votre appareil et déchiffrés sur celui de l'autre. Les notifications sont déchiffrées sur le téléphone."),
            ("Retrouvez les médias", "Les photos et fichiers envoyés sont dans la galerie du chat, sans défiler à l'infini."),
        ],
        "faq": [
            ("Qui est dans le chat ?", "Tous les membres de la famille, et personne d'autre. Il n'y a pas de groupe à créer."),
            ("Puis-je le désactiver ?", "Oui, depuis les Réglages. Les autres continuent d'échanger et vous retrouvez les messages en le réactivant."),
            ("Le chat fonctionne-t-il sur le web ?", "Oui, avec les mêmes messages et le même chiffrement que sur le téléphone."),
        ],
    },
    "salute": {
        "title": "Santé des enfants : consultations, vaccins, dossier médical",
        "short": "L'historique clinique de chaque membre — consultations, examens, vaccins, traitements — avec les comptes rendus joints et un dossier à montrer au médecin. Avec Apple Health et Health Connect.",
        "lead": "Quand le pédiatre demande « quand a eu lieu le dernier rappel ? », la réponse est ici, avec le compte rendu à côté. Et les données du téléphone — pas, fréquence cardiaque, entraînements — arrivent toutes seules.",
        "steps": [
            ("Enregistrez consultations et examens", "Date, médecin, résultat, compte rendu joint. Une consultation payante devient aussi une dépense."),
            ("Tenez les vaccins à jour", "Le carnet de vaccination de chaque enfant, avec les rappels dans le calendrier."),
            ("Montrez le dossier médical", "Un document récapitulatif, à jour, à ouvrir au cabinet ou à envoyer à un nouveau médecin."),
        ],
        "faq": [
            ("Les données de santé sont-elles chiffrées ?", "Oui : comptes rendus et pièces jointes sont chiffrés avec la clé de la famille, et les fiches cliniques ne sont lisibles que par les membres."),
            ("Qu'est-ce qui arrive d'Apple Health / Health Connect ?", "Pas, fréquence cardiaque, tension artérielle, SpO₂, calories actives, entraînements et distance, seulement si vous l'autorisez."),
            ("Qu'apporte l'offre Pro ?", "Des plans alimentaires et d'entraînement générés par l'IA selon le profil, et une analyse mensuelle de l'historique de santé."),
        ],
    },
    "casa": {
        "title": "Maison : garanties, entretien et échéances",
        "short": "Les appareils avec leur garantie et leur entretien, et les échéances de la maison — factures, taxes, contrats — avec rappels et reçus.",
        "lead": "La chaudière, le lave-linge, l'assurance habitation, la taxe d'ordures ménagères : des choses qui expirent et dont un seul parent se souvient d'habitude. Ici, elles le rappellent aux deux.",
        "steps": [
            ("Recensez vos biens", "Marque, modèle, date d'achat, garantie, notice en PDF. La fin de la garantie va dans le calendrier."),
            ("Suivez l'entretien", "Entretien de la chaudière, filtres, climatisation : quand il a été fait et quand il est prévu."),
            ("Échéances et paiements", "Factures, taxes et contrats avec montant, rappel et reçu joint ; une fois payés, ils deviennent des dépenses."),
        ],
        "faq": [
            ("Les échéances préviennent-elles tout le monde ?", "Oui, le rappel arrive aux membres de la famille qui ont activé les notifications."),
            ("Puis-je joindre le reçu ?", "Oui : il va dans Documents, chiffré, lié à l'échéance."),
            ("Quelle différence avec Véhicules ?", "Véhicules a les échéances propres à la voiture — taxe, assurance, contrôle technique — et les interventions au garage."),
        ],
    },
    "veicoli": {
        "title": "Véhicules : taxe, assurance, contrôle technique",
        "short": "Une fiche par voiture avec les échéances qui comptent — taxe, assurance, contrôle technique — et les interventions au garage avec coût et reçu.",
        "lead": "Les voitures de la famille ont des échéances qui coûtent cher si on les oublie. Ici, elles sont réunies sur une seule fiche, avec l'historique des interventions et leur coût.",
        "steps": [
            ("Ajoutez le véhicule", "Immatriculation, modèle, kilométrage. Les échéances de taxe, d'assurance et de contrôle technique vont dans le calendrier avec leurs rappels."),
            ("Enregistrez les interventions", "Entretien, pneus, plaquettes, réparations : date, kilométrage, coût et reçu joint."),
            ("Voyez ce qu'il coûte", "Chaque intervention payante est aussi une dépense de la famille, dans la bonne catégorie."),
        ],
        "faq": [
            ("La taxe est-elle une intervention ?", "Non, c'est une échéance de la fiche du véhicule : vous l'enregistrez une fois et elle revient chaque année."),
            ("Puis-je avoir plusieurs véhicules ?", "Oui, une fiche pour chacun, visible par toute la famille."),
            ("Où vont les reçus ?", "Dans Documents, chiffrés, liés à l'intervention."),
        ],
    },
    "animali": {
        "title": "Animaux : vaccins et vétérinaire",
        "short": "Le profil de chaque animal avec visites chez le vétérinaire, vaccins, antiparasitaires et documents — carnet de santé et puce — joints.",
        "lead": "Le chien et le chat ont un carnet de santé comme les enfants, et les mêmes choses à retenir : le rappel, l'antipuces, le contrôle annuel.",
        "steps": [
            ("Créez le profil", "Nom, espèce, race, date de naissance, puce électronique, photo."),
            ("Enregistrez les événements", "Vaccins, visites, traitements, avec la date du prochain et un rappel."),
            ("Joignez les documents", "Carnet de santé, passeport, certificats : dans Documents, chiffrés."),
        ],
        "faq": [
            ("Y a-t-il des rappels pour les vaccins ?", "Oui, pour chaque événement vous pouvez fixer la date du prochain et recevoir une alerte."),
            ("Les frais de vétérinaire vont-ils dans les Dépenses ?", "Oui, si vous indiquez un coût, l'événement devient aussi une dépense."),
            ("Combien d'animaux puis-je ajouter ?", "Autant que vous en avez."),
        ],
    },
    "posizione": {
        "title": "Localisation de la famille et zones",
        "short": "Où est chacun, sur une seule carte, avec des alertes quand quelqu'un arrive dans un lieu ou le quitte, et un partage temporaire pour un après-midi.",
        "lead": "Pas un traceur : un partage que chacun active et désactive, avec les alertes vraiment utiles — « il est arrivé à l'école », « elle a quitté le travail ».",
        "steps": [
            ("Partagez quand vous voulez", "Chacun décide s'il partage, en continu ou pour une durée limitée."),
            ("Créez un lieu", "Maison, école, grands-parents : une zone autour de l'endroit, avec une alerte à l'arrivée et au départ."),
            ("Regardez la carte", "Tous les membres qui partagent, avec la dernière mise à jour et le niveau de batterie."),
        ],
        "faq": [
            ("Puis-je arrêter le partage ?", "Oui, à tout moment, et les autres sont prévenus que vous avez arrêté."),
            ("La position est-elle chiffrée ?", "Les coordonnées en temps réel ne sont lisibles que par les membres de la famille et ne sont pas conservées sous forme d'historique."),
            ("Est-ce que ça vide la batterie ?", "Le partage utilise les mises à jour en arrière-plan du système, optimisées pour la consommation."),
        ],
    },
    "viaggi": {
        "title": "Voyages en famille avec itinéraire IA",
        "short": "Un itinéraire jour par jour généré par l'IA pour votre famille, avec les lieux Google sur la carte, « Histoire et territoire », et les photos, dépenses et tâches du voyage.",
        "lead": "Dites où vous allez, avec qui et pour combien de temps : l'IA propose un itinéraire adapté aux enfants avec de vrais lieux sur la carte. Ensuite, le voyage rassemble tout le reste.",
        "steps": [
            ("Décrivez le voyage", "Destination, dates, âge des enfants, rythme. L'IA organise le programme jour par jour."),
            ("Explorez la carte", "Restaurants, parcs et musées de Google, avec horaires et avis ; « Histoire et territoire » raconte l'endroit."),
            ("Vivez le voyage", "Photos, dépenses, tâches et notes du voyage restent dans sa fiche, partagée avec la famille."),
        ],
        "faq": [
            ("Peut-on modifier l'itinéraire ?", "Oui : vous déplacez, retirez et ajoutez des étapes ; l'IA est un point de départ."),
            ("Faut-il l'offre Pro ?", "Oui, la génération de l'itinéraire et les contenus IA nécessitent Pro ou Max."),
            ("Où vont les billets ?", "Dans le Wallet, lus depuis le PDF ; depuis le voyage, vous les retrouvez d'un toucher."),
        ],
    },
    "assistente-ai": {
        "title": "Assistant IA de la famille",
        "short": "Un assistant qui connaît le calendrier, les dépenses, la santé et les documents de la famille, et qui agit : il crée événements, tâches et dépenses, et lit les documents que vous importez.",
        "lead": "Pas un chat générique : un assistant qui a le contexte de votre famille, qui répond à « quand a eu lieu le rappel antitétanique ? » avec la date, et qui transforme « note 40 € chez le dentiste » en dépense.",
        "steps": [
            ("Demandez", "En langage naturel, depuis le téléphone ou le web. L'assistant répond avec vos données, pas avec celles d'internet."),
            ("Laissez-le agir", "Événements, tâches, dépenses : il les crée pour vous et vous les montre avant d'enregistrer."),
            ("Importez un document", "Une facture ou un compte rendu : l'IA le lit et propose quoi enregistrer — dépense, échéance, consultation."),
        ],
        "faq": [
            ("Quelles données l'IA voit-elle ?", "Uniquement celles que vous choisissez de partager, demande par demande ; pour le contexte Santé, vous pouvez choisir un résumé ou être interrogé à chaque fois."),
            ("Est-il inclus dans l'offre Free ?", "L'offre Free comprend 5 messages d'essai, une seule fois ; une utilisation continue nécessite Pro ou Max."),
            ("Qu'est-ce que l'« esprit proactif » ?", "Avec Pro, l'assistant prépare de lui-même un briefing le matin, un bilan hebdomadaire et une analyse mensuelle."),
        ],
    },
    "famiglia": {
        "title": "Famille, profils et invitations",
        "short": "Un profil pour chaque parent et chaque enfant, une invitation par lien ou QR qui transporte la clé de chiffrement, et plusieurs familles pour ceux qui en ont besoin.",
        "lead": "Tout dans KidBox est « familial » : la famille se crée en une minute, l'autre parent la rejoint avec un lien, et dès lors vous voyez les mêmes choses.",
        "steps": [
            ("Créez la famille", "Nom, premier enfant, votre nom : l'assistant de configuration fait le reste et génère la clé de chiffrement."),
            ("Invitez votre partenaire", "Un lien à envoyer ou un QR à scanner, valables 24 heures et une seule fois : la clé voyage à l'intérieur, protégée."),
            ("Ajoutez les enfants", "Un profil pour chacun, avec date de naissance et photo ; les fiches santé et école se rattachent au profil."),
        ],
        "faq": [
            ("Puis-je faire partie de deux familles ?", "Oui, par exemple une famille recomposée et les grands-parents : vous passez de l'une à l'autre dans les Réglages."),
            ("Et si je perds mon téléphone ?", "Connectez-vous depuis un autre appareil : la clé de la famille est récupérée depuis le compte et les données redeviennent lisibles."),
            ("Combien de personnes peuvent rejoindre la famille ?", "Cela dépend de l'offre ; Free couvre une famille de deux parents."),
        ],
    },
}
