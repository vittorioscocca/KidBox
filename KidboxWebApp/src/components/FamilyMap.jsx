import { useEffect, useRef } from "react";
import "leaflet/dist/leaflet.css";
import "./FamilyMap.css";

/**
 * Mappa con i membri che condividono e le zone salvate.
 *
 * Usa Leaflet con tile OpenStreetMap: non richiede chiave API né consumi a
 * chiamata, a differenza di Google Maps già usato altrove per i Luoghi.
 */
/**
 * Nome e URL arrivano da altri membri e finiscono dentro l'HTML del marker:
 * vanno neutralizzati, altrimenti un nome con del markup verrebbe interpretato.
 */
function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[c]);
}

function escapeAttr(value) {
  return escapeHtml(value).replace(/`/g, "&#96;");
}

export default function FamilyMap({ people, zones, onMapClick, focus, selfPosition, layer = "map" }) {
  const containerRef = useRef(null);
  const mapRef = useRef(null);
  const layersRef = useRef({ people: null, zones: null });
  const tilesRef = useRef({});
  const clickRef = useRef(onMapClick);
  clickRef.current = onMapClick;

  useEffect(() => {
    let cancelled = false;

    (async () => {
      const L = (await import("leaflet")).default;
      if (cancelled || !containerRef.current || mapRef.current) return;

      const map = L.map(containerRef.current, { zoomControl: true }).setView(
        [41.9028, 12.4964], // Roma: centro neutro finché non arrivano posizioni
        5
      );
      // Entrambe le sorgenti sono utilizzabili senza chiave API: OSM per la
      // mappa, Esri World Imagery per il satellite.
      tilesRef.current.map = L.tileLayer(
        "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
        { attribution: "© OpenStreetMap", maxZoom: 19 }
      );
      tilesRef.current.satellite = L.tileLayer(
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
        { attribution: "© Esri, Maxar, Earthstar Geographics", maxZoom: 19 }
      );
      tilesRef.current[layer === "satellite" ? "satellite" : "map"].addTo(map);

      map.on("click", (e) => clickRef.current?.(e.latlng.lat, e.latlng.lng));

      mapRef.current = map;
      layersRef.current.people = L.layerGroup().addTo(map);
      layersRef.current.zones = L.layerGroup().addTo(map);
      layersRef.current.self = L.layerGroup().addTo(map);
      redraw(L);
    })();

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Ridisegna marker e zone a ogni aggiornamento realtime.
  useEffect(() => {
    (async () => {
      if (!mapRef.current) return;
      const L = (await import("leaflet")).default;
      redraw(L);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [people, zones, selfPosition]);

  useEffect(() => {
    const map = mapRef.current;
    const tiles = tilesRef.current;
    if (!map || !tiles.map || !tiles.satellite) return;
    const wanted = layer === "satellite" ? tiles.satellite : tiles.map;
    const other = layer === "satellite" ? tiles.map : tiles.satellite;
    if (map.hasLayer(other)) map.removeLayer(other);
    if (!map.hasLayer(wanted)) wanted.addTo(map);
  }, [layer]);

  useEffect(() => {
    if (!focus || !mapRef.current) return;
    // Una richiesta esplicita (centra su di me, tocco su un membro o su una
    // zona) vince sull'inquadratura automatica, che da qui in poi resta ferma.
    mapRef.current._didInitialFit = true;
    mapRef.current.setView([focus.lat, focus.lon], focus.zoom ?? 15);
  }, [focus]);

  function redraw(L) {
    const { people: peopleLayer, zones: zonesLayer, self: selfLayer } = layersRef.current;
    if (!peopleLayer || !zonesLayer) return;

    peopleLayer.clearLayers();
    zonesLayer.clearLayers();
    selfLayer?.clearLayers();

    // Puntino della propria posizione: solo indicativo, non viene condiviso con
    // nessuno finché non si attiva esplicitamente la condivisione.
    if (selfLayer && selfPosition) {
      L.circleMarker([selfPosition.lat, selfPosition.lon], {
        radius: 7,
        color: "#fff",
        weight: 2,
        fillColor: "#2196F3",
        fillOpacity: 1,
      }).addTo(selfLayer);
      if (selfPosition.accuracy) {
        L.circle([selfPosition.lat, selfPosition.lon], {
          radius: selfPosition.accuracy,
          color: "#2196F3",
          weight: 1,
          fillColor: "#2196F3",
          fillOpacity: 0.08,
        }).addTo(selfLayer);
      }
    }

    (zones ?? []).forEach((z) => {
      if (z.latitude == null || z.longitude == null) return;
      L.circle([z.latitude, z.longitude], {
        radius: z.radius ?? 100,
        color: "#E8833A",
        weight: 2,
        fillColor: "#E8833A",
        fillOpacity: 0.12,
      })
        .bindTooltip(`${z.emoji ?? "📍"} ${z.name ?? ""}`, { permanent: false })
        .addTo(zonesLayer);
    });

    const bounds = [];
    (people ?? []).forEach((p) => {
      if (p.latitude == null || p.longitude == null) return;
      const initial = (p.name || "?").trim().charAt(0).toUpperCase();
      // L'iniziale sta sempre sotto, l'avatar la copre quando carica: se l'URL
      // è scaduto o irraggiungibile `onerror` toglie l'immagine e resta il pin
      // leggibile, senza costruire elementi da codice inline.
      const inner =
        `<span class="pin-initial">${escapeHtml(initial)}</span>` +
        (p.avatarURL
          ? `<img src="${escapeAttr(p.avatarURL)}" alt="" onerror="this.remove()" />`
          : "");
      const icon = L.divIcon({
        className: "person-pin",
        html: inner,
        iconSize: [40, 40],
        iconAnchor: [20, 20],
      });
      L.marker([p.latitude, p.longitude], { icon })
        .bindTooltip(p.name || "", { direction: "top", offset: [0, -14] })
        .addTo(peopleLayer);
      bounds.push([p.latitude, p.longitude]);
    });

    // Inquadratura automatica UNA SOLA VOLTA, all'arrivo delle prime posizioni.
    // Rifarla a ogni ridisegno riporterebbe la vista sui membri annullando ogni
    // spostamento successivo — compreso il "centra su di me", che imposta la
    // vista prima che questo redraw (asincrono) sia arrivato in fondo.
    if (bounds.length && !mapRef.current._didInitialFit) {
      mapRef.current._didInitialFit = true;
      if (bounds.length === 1) mapRef.current.setView(bounds[0], 15);
      else mapRef.current.fitBounds(bounds, { padding: [40, 40] });
    }
  }

  return <div className="family-map" ref={containerRef} />;
}
