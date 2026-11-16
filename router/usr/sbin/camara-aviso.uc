#!/usr/bin/ucode
// camara-aviso.uc - Avisos de la camara IP al telefono, sin depender de la PC.
//
// La camara (familia XM / iCSee) tiene una opcion "servidor de alarmas": cada vez
// que detecta algo abre una conexion TCP y manda un JSON con el evento. Este
// demonio es ese servidor: escucha, se queda solo con los eventos de PERSONA y
// publica un aviso en ntfy (https://ntfy.sh), que lo entrega al telefono.
//
// Configuracion: /etc/config/camara_aviso (ver router/etc/config/camara_aviso).
// Registro: solo a syslog (logread -e camara-aviso). Nada se escribe en flash.
'use strict';

import * as uloop from "uloop";
import * as socket from "socket";
import { cursor } from "uci";

const cfg = cursor().get_all("camara_aviso", "main") || {};

const PUERTO       = +(cfg.puerto || 15002);
const ORIGENES     = cfg.origen || [];            // IPs que pueden mandar alarmas
const PATRON       = regexp(cfg.patron || "human", "i");
const ENFRIAMIENTO = +(cfg.enfriamiento || 60);   // segundos entre avisos
const SERVIDOR     = cfg.servidor || "https://ntfy.sh";
const TEMA         = cfg.tema || "";
const TITULO       = cfg.titulo || "Camara";
const MENSAJE      = cfg.mensaje || "Persona detectada";
const PRIORIDAD    = cfg.prioridad || "high";
const MAX_BUFFER   = 16384;

let ultimo_aviso = 0;
let conexiones = {};   // fd -> { sock, handle, buf, timer }

function log(txt) {
	warn("camara-aviso: " + txt + "\n");
}

// Las comillas simples romperian el comando de shell: se quitan.
function limpio(s) {
	return replace("" + s, /['\\\n\r]/g, "");
}

function avisar(evento) {
	let ahora = time();
	if (ahora - ultimo_aviso < ENFRIAMIENTO) {
		log(`aviso omitido (enfriamiento): ${evento}`);
		return;
	}
	ultimo_aviso = ahora;
	if (!TEMA) {
		log("falta 'tema' en /etc/config/camara_aviso: no se envia nada");
		return;
	}
	// En segundo plano: curl puede tardar y no debe frenar la escucha.
	system(sprintf(
		"curl -s -m 20 -o /dev/null -H 'Title: %s' -H 'Priority: %s' -H 'Tags: rotating_light' -d '%s' '%s/%s' &",
		limpio(TITULO), limpio(PRIORIDAD), limpio(MENSAJE), limpio(SERVIDOR), limpio(TEMA)));
	log(`aviso enviado: ${evento}`);
}

function procesar(obj) {
	// Segun el firmware, el evento viene en la raiz o dentro de "AlarmInfo".
	let info = (type(obj.AlarmInfo) == "object") ? obj.AlarmInfo : obj;
	let evento = info.Event;
	if (!evento)
		return;
	let estado = info.Status || "Start";
	log(`evento ${evento} (${estado})`);
	if (estado == "Start" && match(evento, PATRON))
		avisar(evento);
}

// La camara manda una cabecera binaria y despues el JSON: se busca el primer
// objeto {...} completo dentro de lo recibido, contando llaves.
function extraer(c) {
	while (true) {
		let ini = index(c.buf, "{");
		if (ini < 0) {
			c.buf = "";
			return;
		}
		let nivel = 0, fin = -1;
		for (let i = ini; i < length(c.buf); i++) {
			let ch = substr(c.buf, i, 1);
			if (ch == "{") nivel++;
			else if (ch == "}" && --nivel == 0) { fin = i; break; }
		}
		if (fin < 0) {
			c.buf = substr(c.buf, ini);   // incompleto: esperar mas datos
			return;
		}
		let texto = substr(c.buf, ini, fin - ini + 1);
		c.buf = substr(c.buf, fin + 1);
		try {
			procesar(json(texto));
		} catch (e) {
			log("JSON invalido: " + substr(texto, 0, 120));
		}
	}
}

function cerrar(fd) {
	let c = conexiones[fd];
	if (!c)
		return;
	c.handle.delete();
	c.timer.cancel();
	c.sock.close();
	delete conexiones[fd];
}

function aceptar(servidor) {
	let sock = servidor.accept();
	if (!sock)
		return;
	let origen = sock.peername()?.address;
	if (length(ORIGENES) && index(ORIGENES, origen) < 0) {
		log(`conexion rechazada de ${origen}`);
		sock.close();
		return;
	}
	let fd = sock.fileno();
	let c = { sock, buf: "" };
	c.handle = uloop.handle(fd, function() {
		let datos = sock.recv(4096);
		if (datos == null || datos == "") {
			cerrar(fd);
			return;
		}
		c.buf += datos;
		if (length(c.buf) > MAX_BUFFER)
			c.buf = "";
		extraer(c);
	}, uloop.ULOOP_READ);
	// Si la camara deja la conexion abierta sin mandar nada, se libera sola.
	c.timer = uloop.timer(60000, () => cerrar(fd));
	conexiones[fd] = c;
}

uloop.init();

let servidor = socket.listen("0.0.0.0", PUERTO, null, 8, true);
if (!servidor) {
	log(`no pude escuchar en el puerto ${PUERTO}: ${socket.error()}`);
	exit(1);
}
let escucha = uloop.handle(servidor.fileno(), () => aceptar(servidor), uloop.ULOOP_READ);

log(`escuchando en el puerto ${PUERTO}; origenes permitidos: ${join(", ", ORIGENES) || "cualquiera"}`);
uloop.run();
