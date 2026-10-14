"""Prove della UI reale Quickshell con eventi IPC isolati, senza kernel/root.

Eseguire da una sessione grafica: python tests/test_fucina2_gui.py
FUCINA_GUI_ARTIFACT_DIR sceglie dove conservare screenshot e log Quickshell.
La compilazione/il boot reali sono verifiche distinte da queste fixture.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("qs") and (os.getenv("WAYLAND_DISPLAY") or os.getenv("DISPLAY")),
                     "richiede Quickshell e una sessione grafica")
class FucinaGuiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="fucina2-gui-")
        cls.stage = Path(cls.temp.name)
        cls.artifacts = Path(os.environ.get("FUCINA_GUI_ARTIFACT_DIR", cls.stage / "artefatti"))
        cls.artifacts.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "fucina2/Fucina2.qml", cls.stage)
        for name in ("core", "theme", "ui"):
            (cls.stage / name).symlink_to(ROOT / "minerva-shell" / name, target_is_directory=True)
        # Un override esistente impedisce ogni ripiego sul canale autentico.
        token = cls.stage / "canale"
        token.write_text("fixture-isolata=nessun-canale\n")
        cls.app = cls.stage / "app.qml"
        cls.app.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "core" as Core
import "."
ShellRoot {
    Fucina2 { id: win; visible: true; title: "Fucina 2 · verifica automatica" }
    // Il contenitore include il fondo della finestra: catturare soltanto il
    // Flickable farebbe perdere il fondo sotto le superfici trasparenti.
    Item { id: immagine; parent: win.contentItem; anchors.fill: parent }
    Component.onCompleted: {
        var figli = [];
        for (var i = 0; i < win.contentItem.children.length; i++)
            if (win.contentItem.children[i] !== immagine) figli.push(win.contentItem.children[i]);
        figli.forEach(function (f) { f.parent = immagine; });
    }
    function trova(oggetto, nome) {
        if (oggetto.objectName === nome) return oggetto;
        var figli = oggetto.children || [];
        for (var i = 0; i < figli.length; i++) {
            var trovato = trova(figli[i], nome);
            if (trovato) return trovato;
        }
        return null;
    }
    IpcHandler {
        target: "fixture"
        function applica(testo: string): string {
            var d = JSON.parse(testo);
            if (d.anteprima) win.ricettaPreview = d.anteprima;
            win.pagina = d.pagina || "compila";
            win.popupKernelPronto = false;
            if (d.evento === "fatto") Core.Ipc.fucinaFatto(d.payload);
            else if (d.evento === "verifica") Core.Ipc.fucinaVerifica(d.payload);
            else if (d.evento === "passo") Core.Ipc.fucinaPasso(d.payload);
            else if (d.evento === "kernel") Core.Ipc.fucinaKernel(d.payload);
            else if (d.evento === "cache-recuperata") Core.Ipc.fucinaCacheRecuperata(d.payload);
            else if (d.evento === "rilievo") Core.Ipc.fucinaRilievo(d.payload);
            else Core.Ipc.fucinaStato(d.payload);
            return "ok";
        }
        function stato(): string {
            var stato = trova(win.contentItem, "statoCompilazione");
            var avvisi = trova(win.contentItem, "avvisiCompilazione");
            var log = trova(win.contentItem, "apriLogCompleto");
            var verifica = trova(win.contentItem, "verificaDispositivi");
            var nome = trova(win.contentItem, "nomeRicettaCompilazione");
            var riepilogo = trova(win.contentItem, "riepilogoCompilazione");
            return JSON.stringify({pagina: win.pagina, compilando: win.compilando,
                errore: win.erroreCompilazione, secondi: win.secondiCompilazione,
                log: win.logCompilazione, logVisible: log && log.visible,
                etichetta: stato && stato.text, avvisi: avvisi && avvisi.text,
                avvisiVisible: avvisi && avvisi.visible, verifica: verifica && verifica.text,
                nomeRicetta: nome && nome.text, riepilogo: riepilogo && riepilogo.text,
                recupero: trova(win.contentItem, "statoRecuperoCache").text,
                recuperoAbilitato: trova(win.contentItem, "riapriCache").enabled,
                recuperoInCorso: win.staRiaprendoCache,
                prerequisiti: trova(win.contentItem, "statoPrerequisitiKernel").text,
                confermaKernel: win.confermaKernel, kernelImpegnato: win.kernelImpegnato,
                erroreKernel: win.erroreKernel,
                supportoNativo: win.supportoNativo, targetNativo: win.targetNativo});
        }
        function fondo(): string {
            trova(win.contentItem, "contenutoFucina2").forceLayout();
            var s = trova(win.contentItem, "scorrimentoFucina2");
            s.contentY = Math.max(0, s.contentHeight - s.height);
            return "ok";
        }
        function rivela(nome: string): string {
            trova(win.contentItem, "contenutoFucina2").forceLayout();
            var c = trova(win.contentItem, nome);
            var s = trova(win.contentItem, "scorrimentoFucina2");
            s.contentY = Math.max(0, Math.min(s.contentHeight - s.height,
                s.contentY + c.mapToItem(win.contentItem, 0, 0).y - 70));
            return "ok";
        }
        function configura(testo: string): string {
            var d = JSON.parse(testo);
            win.compilando = false; win.mostraUltimaBuild = false;
            win.esitoCompilazione = null; win.confermaCompilazione = false;
            win.popupKernelPronto = false; win.confermaKernel = false;
            win.messaggioRecuperoCache = ""; win.esitoRecuperoCache = null;
            win.staRiaprendoCache = false; win.kernelImpegnato = "";
            win.pagina = d.pagina || "configura";
            if (d.rilievo) win.rilievo = d.rilievo;
            if (d.versione) win.versioneKernel = d.versione;
            win.moduliEspansi = false; win.presetUso = [];
            win.lavoriCompilazione = d.lavori || 0;
            win.ricettaPreview = d.ricetta || null;
            win.staCalcolandoRicetta = false;
            // Il compositore può mantenere la geometria della finestra.
            // Ridimensiona il viewport posseduto dal motore QML per provare
            // il layout piccolo senza dipendere dalle policy del desktop.
            immagine.anchors.fill = undefined;
            immagine.width = d.width || 1080; immagine.height = d.height || 740;
            return "ok";
        }
        function clicca(nome: string): string {
            var c = trova(win.contentItem, nome);
            if (!c) return "mancante";
            if (!c.enabled) return "disabilitato";
            c.clicked(null);
            return "ok";
        }
        function richiediKernel(testo: string): string {
            var d = JSON.parse(testo);
            win.chiediAzioneKernel(d.azione, d.rilascio);
            return "ok";
        }
        function eseguiKernel(): string { win.eseguiAzioneKernel(); return "ok"; }
        function controllo(nome: string): string {
            var c = trova(win.contentItem, nome);
            var p = c ? c.mapToItem(win.contentItem,0,0) : {x:0,y:0};
            var scroll = trova(win.contentItem, "scorrimentoFucina2");
            return JSON.stringify({trovato: !!c, height: c && c.height, y: p.y,
                viewportHeight: immagine.height, contentHeight: scroll.contentHeight,
                contentY: scroll.contentY, scrollHeight: scroll.height,
                preset: win.presetUso, sorgente: win.sorgente, compilatore: win.compilatore,
                lavori: win.lavoriCompilazione,
                conferma: win.confermaCompilazione, pagina: win.pagina,
                moduliEspansi: win.moduliEspansi, visible: c && c.visible,
                enabled: c && c.enabled, text: c && c.text});
        }
        function cattura(percorso: string): string {
            return immagine.grabToImage(function (r) { r.saveToFile(percorso); }) ? "richiesta" : "non riuscita";
        }
    }
}
''')
        env = dict(os.environ, MINERVA_TOKEN_FILE=str(token), MINERVA_SESSIONE="fucina-gui-fixture",
                   MINERVA_CONFIG_DIR=str(cls.stage / "config"), XDG_CONFIG_HOME=str(cls.stage / "config"),
                   XDG_STATE_HOME=str(cls.stage / "state"), XDG_CACHE_HOME=str(cls.stage / "cache"))
        cls.log = (cls.artifacts / "quickshell.log").open("w")
        cls.process = subprocess.Popen(["qs", "-n", "-p", str(cls.app)], env=env,
                                       stdout=cls.log, stderr=subprocess.STDOUT)
        try:
            cls.attendi(lambda: cls.rpc("stato", fail=False))
        except Exception:
            cls.tearDownClass()
            raise
        print(f"\nArtefatti GUI: {cls.artifacts}")

    @classmethod
    def tearDownClass(cls):
        if cls.process.poll() is None:
            cls.process.terminate()
            try:
                cls.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                cls.process.kill()
                cls.process.wait(timeout=5)
        cls.log.close()
        cls.temp.cleanup()

    @classmethod
    def attendi(cls, verifica):
        limite = time.monotonic() + 8
        while time.monotonic() < limite:
            if cls.process.poll() is not None:
                raise AssertionError((cls.artifacts / "quickshell.log").read_text()[-6000:])
            value = verifica()
            if value:
                return value
            time.sleep(0.05)
        raise AssertionError("Quickshell non ha restituito l'artefatto richiesto entro 8 secondi")

    @classmethod
    def rpc(cls, function, *args, fail=True):
        r = subprocess.run(["qs", "ipc", "-p", str(cls.app), "call", "fixture", function, *args],
                           capture_output=True, text=True, timeout=3)
        if r.returncode:
            if fail:
                raise AssertionError(r.stdout + r.stderr)
            return None
        return r.stdout.strip()

    def applica(self, evento, payload, pagina="compila"):
        self.rpc("applica", json.dumps(dict(evento=evento, payload=payload, pagina=pagina)))
        return json.loads(self.rpc("stato"))

    def screenshot(self, nome):
        self.rpc("fondo")
        path = self.artifacts / f"{nome}.png"
        path.unlink(missing_ok=True)
        self.assertEqual(self.rpc("cattura", str(path)), "richiesta")
        self.attendi(lambda: path.exists() and path.stat().st_size > 1000)

    def test_1_successo_ripristinato_mostra_durata_avvisi_e_log(self):
        s = self.applica("stato", dict(inCorso=False, secondi=42, log="/tmp/diario-fixture.log",
            righe=["  CC [M] fixture.o"], passi={},
            esito=dict(ok=True, secondi=42, avvisi=["BORE assente dai sorgenti della fixture."])))
        self.assertFalse(s["compilando"])
        self.assertEqual(s["secondi"], 42)
        self.assertIn("Completato", s["etichetta"])
        self.assertTrue(s["logVisible"])
        self.assertTrue(s["avvisiVisible"])
        self.assertIn("BORE assente", s["avvisi"])
        self.screenshot("successo-con-avvisi")

    def test_2_errore_non_diventa_completato(self):
        s = self.applica("fatto", dict(ok=False, annullato=False, secondi=3,
            errore="Kconfig non ha accettato il target della fixture.", avvisi=[], log="/tmp/errore.log"))
        self.assertIn("Non riuscita", s["etichetta"])
        self.assertIn("Kconfig", s["errore"])
        self.assertEqual(s["secondi"], 3)
        self.assertTrue(s["logVisible"])
        self.screenshot("errore-kconfig")

    def test_3_annullamento_conserva_il_log(self):
        s = self.applica("fatto", dict(ok=False, annullato=True, secondi=5,
            errore="Fermata.", avvisi=[], log="/tmp/annullata.log"))
        self.assertFalse(s["compilando"])
        self.assertIn("Interrotta", s["etichetta"])
        self.assertTrue(s["logVisible"])

    def test_4_riapertura_durante_build_ripristina_stato_e_log(self):
        s = self.applica("stato", dict(inCorso=True, secondi=19, log="/tmp/in-corso.log",
            passo="Compila", passi={"compila": "via"}, righe=["  CC      fixture.o"],
            avanzamento=dict(fase="compila", fatti=71, attesi=100)))
        self.assertTrue(s["compilando"])
        self.assertIn("71 / 100 file", s["etichetta"])
        self.assertTrue(s["logVisible"])
        self.applica("fatto", dict(ok=False, annullato=True, secondi=19, errore="Fermata.", avvisi=[]))

    def test_5_verifica_dispositivi_resta_in_fucina2(self):
        s = self.applica("verifica", dict(ok=True, applicabile=True, aPosto=57,
            orfani=[], assenti=[dict(driver="fixture-a"), dict(driver="fixture-b")]), pagina="kernel")
        self.assertEqual(s["pagina"], "kernel")
        self.assertIn("57 dispositivi hanno un driver", s["verifica"])
        self.assertIn("0 presenti senza driver, 2 non ritrovati", s["verifica"])
        self.screenshot("verifica-dispositivi")

    def test_6_build_avviata_da_altro_client_attiva_la_finestra(self):
        s = self.applica("passo", dict(id="compila", titolo="Compila", stato="via", log="/tmp/altro-client.log"))
        self.assertTrue(s["compilando"])
        self.assertEqual(s["pagina"], "compila")
        self.assertEqual(s["log"], "/tmp/altro-client.log")
        self.applica("fatto", dict(ok=False, annullato=True, secondi=1, errore="Fermata.", avvisi=[]))

    def test_7_ricetta_in_esecuzione_prevale_sull_anteprima_corrente(self):
        ricetta = dict(rilascio="7.2.9-fucina-reale", quanti=12,
                       scelte=dict(sorgente="cachyos", compilatore="clang", lto=True, nativo=True,
                                   base="in-uso", scorte=[], provaAvvio=False),
                       passi=[dict(id="compila", titolo="Compila CachyOS", spiega="Fixture della ricetta eseguita")])
        self.rpc("applica", json.dumps(dict(evento="stato", anteprima=dict(rilascio="7.2.9-fucina-diverso",
            scelte=dict(sorgente="vanilla", compilatore="gcc"), quanti=999, passi=[]),
            payload=dict(inCorso=True, secondi=19, log="/tmp/reale.log", passo="Compila", ricetta=ricetta,
                         passi={}, righe=[], avanzamento={}))))
        s = json.loads(self.rpc("stato"))
        self.assertIn("7.2.9-fucina-reale", s["nomeRicetta"])
        self.assertNotIn("diverso", s["nomeRicetta"])
        self.assertIn("Sorgente: CachyOS", s["riepilogo"])
        self.assertIn("Clang con ThinLTO", s["riepilogo"])
        self.screenshot("ricetta-reale-ripristinata")
        s = self.applica("fatto", dict(ok=False, annullato=True, secondi=20, errore="Fermata.", avvisi=[], ricetta=ricetta))
        self.assertIn("7.2.9-fucina-reale", s["nomeRicetta"])


    def test_8_profili_esclusivi_e_sorgenti_compilatori_selezionabili(self):
        self.rpc('configura', json.dumps(dict(rilievo=dict(macchina={},moduli=[],scorte=[],presets=[
            dict(id='gaming',nome='Gioco',hz=1000,prelazione='full'),
            dict(id='ufficio',nome='Ufficio',hz=300,prelazione='voluntary')]))))
        for name,expected in [('preset-gaming',['gaming']),('preset-ufficio',['ufficio']),('preset-ufficio',[]),('preset-gaming',['gaming']),('preset-',[])]:
            self.assertEqual(self.rpc('clicca',name),'ok')
            self.assertEqual(json.loads(self.rpc('controllo',name))['preset'],expected)
        for source in ['cachyos','vanilla']:
            self.assertEqual(self.rpc('clicca','sorgente-'+source),'ok')
            self.assertEqual(json.loads(self.rpc('controllo','sorgente-'+source))['sorgente'],source)
        for compiler in ['clang','gcc']:
            self.assertEqual(self.rpc('clicca','compilatore-'+compiler),'ok')
            self.assertEqual(json.loads(self.rpc('controllo','compilatore-'+compiler))['compilatore'],compiler)

    def test_9_comprimere_nasconde_tutti_i_155_moduli(self):
        mods=[dict(nome=f'fixture_{i}',famiglia='altro',diSerie=True,fonti=['modprobed']) for i in range(155)]
        self.rpc('configura',json.dumps(dict(rilievo=dict(macchina={},moduli=mods,scorte=[],presets=[]))))
        c=lambda:json.loads(self.rpc('controllo','contenitoreDecisioniModuli'))
        self.assertEqual(c()['height'],0)
        self.assertEqual(self.rpc('clicca','comprimereModuli'),'ok')
        self.attendi(lambda:c()['height']>155*50)
        self.assertEqual(self.rpc('clicca','comprimereModuli'),'ok')
        self.assertEqual(c()['height'],0)
        self.screenshot('155-moduli-compressi')

    def test_a_pulsante_finale_raggiungibile_a_780_per_560(self):
        self.rpc('configura',json.dumps(dict(width=780,height=560)))
        # Lascia aggiornare implicitHeight e i binding delle card.
        time.sleep(0.15)
        self.rpc('fondo')
        c=json.loads(self.rpc('controllo','rivediCompilazione'))
        self.screenshot('configurazione-780-560')
        self.assertTrue(c['trovato'])
        self.assertGreaterEqual(c['y'],0)
        self.assertLessEqual(c['y']+c['height'],c['viewportHeight'])
        self.assertEqual(self.rpc('clicca','rivediCompilazione'),'ok')
        self.assertEqual(json.loads(self.rpc('controllo','rivediCompilazione'))['pagina'],'compila')

    def test_b_prerequisiti_bloccano_e_conferma_resta_nella_finestra(self):
        recipe=dict(rilascio='7.2.9-fucina-fixture',quanti=1,passi=[],avvisi=[],requisitiMancanti=['clang'])
        self.rpc('configura',json.dumps(dict(pagina='compila',ricetta=recipe)))
        self.assertEqual(self.rpc('clicca','azioneCompilazione'),'disabilitato')
        self.assertFalse(json.loads(self.rpc('controllo','azioneCompilazione'))['conferma'])
        recipe['requisitiMancanti']=[]
        self.rpc('configura',json.dumps(dict(pagina='compila',ricetta=recipe)))
        self.assertEqual(self.rpc('clicca','azioneCompilazione'),'ok')
        self.assertTrue(json.loads(self.rpc('controllo','confermaOperazioneFucina'))['visible'])
        self.screenshot('conferma-compilazione-a-tema')

    def test_c_recupero_cache_bloccato_con_processi_attivi(self):
        self.rpc('configura',json.dumps(dict(pagina='kernel')))
        s=self.applica('kernel',dict(kernel=[],cache=dict(recupero=dict(
            stato='occupato',recuperabile=False,messaggio='Ci sono ancora processi del lavoro interrotto.'))),pagina='kernel')
        self.assertIn('processi',s['recupero'])
        self.assertFalse(s['recuperoAbilitato'])
        self.assertEqual(self.rpc('clicca','riapriCache'),'disabilitato')
        self.screenshot('recupero-cache-processi-attivi')

    def test_d_recupero_cache_sicuro_e_ricevuta_visibile(self):
        self.rpc('configura',json.dumps(dict(pagina='kernel')))
        s=self.applica('kernel',dict(kernel=[],cache=dict(recupero=dict(
            stato='recuperabile',recuperabile=True,token='fixture',messaggio='I gruppi di lavoro sono terminati.'))),pagina='kernel')
        self.assertTrue(s['recuperoAbilitato'])
        self.assertEqual(self.rpc('clicca','riapriCache'),'ok')
        s=json.loads(self.rpc('stato'))
        self.assertTrue(s['recuperoInCorso']);self.assertFalse(s['recuperoAbilitato'])
        s=self.applica('cache-recuperata',dict(ok=True,messaggio='Cache riaperta. I sorgenti, i kernel e i log sono conservati.'),pagina='kernel')
        self.assertFalse(s['recuperoInCorso']);self.assertIn('conservati',s['recupero'])
        self.assertFalse(s['recuperoAbilitato'])
        self.screenshot('recupero-cache-conserva-dati')

    def kernel_preparato(self, admin=True, pronto=True, prova=None):
        rel='7.2.9-fucina-fixture'
        admin_info=dict(installazionePossibile=admin,rimozionePossibile=admin,
                        controlli=[dict(id='aiutante',ok=admin,messaggio='Aggiorna l’aiutante amministrativo prima di installare o rimuovere kernel.')])
        kernels=[dict(rilascio=rel,pronto=pronto,installato=False,inUso=False,
                      preparazione=dict(ok=pronto,blocchi=[] if pronto else ['Manifest illeggibile. Ricompila questo kernel.'],avvisi=[]))]
        if prova is not None:kernels[0]['provaAvvio']=dict(ok=prova)
        return rel,dict(kernel=kernels,amministrazione=admin_info,cache=dict(recupero=dict(stato='libero')))

    def test_e_helper_vecchio_blocca_prima_della_conferma(self):
        self.rpc('configura',json.dumps(dict(pagina='kernel')))
        rel,info=self.kernel_preparato(admin=False)
        s=self.applica('kernel',info,pagina='kernel')
        self.assertIn('completa i prerequisiti',s['prerequisiti'])
        self.assertEqual(self.rpc('clicca','installa-'+rel),'disabilitato')
        self.rpc('richiediKernel',json.dumps(dict(azione='installa',rilascio=rel)))
        s=json.loads(self.rpc('stato'));self.assertFalse(s['confermaKernel']);self.assertEqual(s['kernelImpegnato'],'')
        self.assertIn('prerequisiti',s['erroreKernel'])
        self.rpc('rivela','statoPrerequisitiKernel')
        self.screenshot('prerequisiti-aiutante-da-aggiornare')

    def test_f_controlli_cambiati_bloccano_la_conferma_e_il_comando(self):
        self.rpc('configura',json.dumps(dict(pagina='kernel')))
        rel,info=self.kernel_preparato()
        self.applica('kernel',info,pagina='kernel')
        self.assertEqual(self.rpc('clicca','installa-'+rel),'ok')
        self.assertTrue(json.loads(self.rpc('stato'))['confermaKernel'])
        info['amministrazione']['installazionePossibile']=False
        self.applica('kernel',info,pagina='kernel')
        self.assertEqual(self.rpc('clicca','confermaAzioneKernel'),'disabilitato')
        self.rpc('eseguiKernel')
        s=json.loads(self.rpc('stato'));self.assertFalse(s['confermaKernel']);self.assertEqual(s['kernelImpegnato'],'')

    def test_g_materiali_incompleti_e_qemu_fallito_non_si_installano(self):
        self.rpc('configura',json.dumps(dict(pagina='kernel')))
        rel,info=self.kernel_preparato(pronto=False)
        self.applica('kernel',info,pagina='kernel')
        self.assertIn('Manifest',json.loads(self.rpc('controllo','preparazione-'+rel))['text'])
        self.assertEqual(self.rpc('clicca','installa-'+rel),'disabilitato')
        rel,info=self.kernel_preparato(prova=False)
        self.applica('kernel',info,pagina='kernel')
        self.assertEqual(self.rpc('clicca','installa-'+rel),'disabilitato')
        self.rpc('rivela','preparazione-'+rel)
        self.screenshot('kernel-con-controlli-da-risolvere')

    def test_h_target_compilatori_distinto_dal_livello_isa(self):
        self.rpc('configura',json.dumps(dict(pagina='panoramica',versione='7.2.9')))
        info=dict(rilascio='7.2.9-fixture',macchina=dict(livelloX86='v3',flagsCpuUniformi=True,flagsCpuCompleti=True),
                  moduli=[],scorte=[],presets=[],targetCompilatori=[
                      dict(compilatore='gcc',rilevato=True,cpu='haswell',tuning='haswell'),
                      dict(compilatore='clang',rilevato=True,cpu='haswell',tuning='')])
        s=self.applica('rilievo',info,pagina='panoramica')
        self.assertTrue(s['supportoNativo'])
        self.assertIn('haswell',json.loads(self.rpc('controllo','target-compilatore-gcc'))['text'])
        self.assertIn('haswell',json.loads(self.rpc('controllo','target-compilatore-clang'))['text'])
        self.assertIn('Confronta',json.loads(self.rpc('controllo','consiglioTargetCpu'))['text'])
        self.rpc('rivela','titoloTargetCompilatori')
        self.screenshot('target-compilatori-haswell')
        self.assertEqual(self.rpc('clicca','rivediTargetCpu'),'ok')
        self.assertEqual(json.loads(self.rpc('stato'))['pagina'],'configura')

    def test_i_cpu_non_uniformi_propongono_generico_e_sonda_assente_resta_esplicita(self):
        self.rpc('configura',json.dumps(dict(pagina='panoramica',versione='7.2.9',width=780,height=560)))
        info=dict(rilascio='7.2.9-fixture',macchina=dict(livelloX86='v2',flagsCpuUniformi=False,flagsCpuCompleti=True),
                  moduli=[],scorte=[],presets=[],targetCompilatori=[
                      dict(compilatore='gcc',rilevato=False,cpu='',messaggio='Compilatore non disponibile.')])
        s=self.applica('rilievo',info,pagina='panoramica')
        self.assertFalse(s['supportoNativo']);self.assertFalse(s['targetNativo'])
        self.assertIn('non sono uniformi',json.loads(self.rpc('controllo','consiglioTargetCpu'))['text'])
        self.assertIn('non disponibile',json.loads(self.rpc('controllo','target-compilatore-gcc'))['text'])
        self.rpc('rivela','titoloTargetCompilatori')
        button=json.loads(self.rpc('controllo','rivediTargetCpu'))
        self.assertGreaterEqual(button['y'],0)
        self.assertLessEqual(button['y']+button['height'],button['viewportHeight'])
        self.screenshot('cpu-non-uniformi-target-generico')

    def test_j_parallelismo_auto_spiegato_e_controlli_partono_dal_consiglio(self):
        p=dict(automatico=True,consigliati=2,effettivi=2,thread=16,
               manualeOltreConsiglio=False,motivo='Auto propone 2 lavori su 16 thread: 2.0 GiB disponibili entro i limiti cgroup.',
               limite='Stima prudente. ThinLTO usa anche thread propri nel linker, non limitati da make -j.')
        self.rpc('configura',json.dumps(dict(width=780,height=560,versione='7.2.9',
            rilievo=dict(macchina=dict(nuclei=16),moduli=[]),ricetta=dict(parallelismo=p))))
        self.assertEqual(json.loads(self.rpc('controllo','lavori-effettivi'))['text'],'Auto · 2 lavori')
        self.assertIn('cgroup',json.loads(self.rpc('controllo','consiglio-parallelismo'))['text'])
        self.assertIn('linker',json.loads(self.rpc('controllo','consiglio-parallelismo'))['text'])
        self.rpc('rivela','consiglio-parallelismo')
        advice=json.loads(self.rpc('controllo','consiglio-parallelismo'))
        self.assertLessEqual(advice['y']+advice['height'],advice['viewportHeight'])
        path=self.artifacts/'parallelismo-memoria-780-560.png'
        self.assertEqual(self.rpc('cattura',str(path)),'richiesta')
        self.attendi(lambda:path.exists() and path.stat().st_size>1000)
        self.assertEqual(self.rpc('clicca','lavori-piu'),'ok')
        self.assertEqual(json.loads(self.rpc('controllo','lavori-piu'))['lavori'],3)

    def test_k_parallelismo_manuale_avvisa_e_auto_attende_la_nuova_ricetta(self):
        p=dict(automatico=False,consigliati=2,effettivi=8,thread=16,
               manualeOltreConsiglio=True,motivo='Auto propone 2 lavori su 16 thread.',
               limite='La memoria viene riletta quando si avvia la compilazione.')
        self.rpc('configura',json.dumps(dict(lavori=8,versione='7.2.9',
            rilievo=dict(macchina=dict(nuclei=16),moduli=[]),ricetta=dict(parallelismo=p))))
        self.assertIn('supera il consiglio',json.loads(self.rpc('controllo','consiglio-parallelismo'))['text'])
        self.assertEqual(json.loads(self.rpc('controllo','lavori-effettivi'))['text'],'8 lavori')
        self.assertEqual(self.rpc('clicca','lavori-auto'),'ok')
        self.assertEqual(json.loads(self.rpc('controllo','lavori-auto'))['lavori'],0)
        self.assertIn('verifica',json.loads(self.rpc('controllo','lavori-effettivi'))['text'])
        self.assertEqual(self.rpc('clicca','lavori-piu'),'disabilitato')


if __name__ == "__main__":
    unittest.main(verbosity=2)
