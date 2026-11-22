import json

OUT = "/Users/jinx/Documents/projeler/CutSense/ios/metadata/version-1.1.0.json"

EN_DESC = """Remove silence from any talking video. CutSense finds the long pauses and dead air in your clip and cuts them out on your iPhone, so your video gets to the point faster.

HOW IT WORKS
1. Choose a video from Photos.
2. Pick a style: Balanced (recommended), Tight or Hardcore.
3. Preview the result and see how much was removed.
4. Open Review cuts to keep any pause you want.
5. Save to Photos or share.

REVIEW EVERY CUT
Every removed pause is listed. Keep the ones that matter, like a beat before a punchline or a breath between two ideas, and cut the rest. Change cuts one by one. The free version keeps up to 3 pauses per video. Pro keeps as many as you want and adds Keep all. Nothing is final until you save.

WHY CREATORS USE IT
- Tighter Reels and Shorts without trimming by hand
- Jump-cut pacing for vlogs, tutorials, interviews and talking-head videos
- Quicker edits for lectures, UGC and product videos
- No watermark on your videos
- No account or sign-up

PRIVATE BY DESIGN
Your video is processed on your device and is never uploaded. Your original stays untouched. CutSense saves the result as a new MP4 that you can keep in Photos or share.

CUTSENSE PRO
An optional one-time purchase. No subscription. Pro removes all ads for good, lets you keep as many pauses as you want, and unlocks Fine-tune, where you set the minimum pause length and how much breathing room stays around your words.

GOOD TO KNOW
- CutSense removes silence. It does not remove filler words like "um", and it does not pick your best takes.
- It works best on clear speech. If a video has little speech, a lot of it will be cut, and the app warns you when that happens.

CutSense is free and supported by ads. Watch an optional short ad to get 24 hours without banner ads. The app is available in English, Turkish, Spanish, Portuguese, German, French, Italian, Japanese and Korean."""

EN_PROMO = "Cut the dead air out of your talking videos. Free, no watermark, and your video never leaves your iPhone."

EN_NEW = """What's new in 1.1.0
- Preview before saving: watch the result and see how much was removed.
- Review every cut and keep any pause you want.
- Balanced is the new default, so your videos don't get over-cut.
- A warning when a video has little speech.
- CutSense Pro: a one-time purchase with no subscription. It removes ads, keeps unlimited pauses and unlocks Fine-tune.
- CutSense is now available in 9 languages.
- Temporary files are cleaned up automatically, and Settings shows the storage used.
- Stability fixes."""


def en(keywords):
    return {"description": EN_DESC, "promotionalText": EN_PROMO, "whatsNew": EN_NEW, "keywords": keywords}


data = {
    "en-US": en("video,cutter,dead air,trim,editor,talking head,reels,shorts,ugc,vlog,gaps,speech,lecture,interview"),
    "en-GB": en("video,cutter,dead air,editor,talking head,reels,shorts,vlog,gaps,speech,trim,interview,lecture,clip"),
    "en-AU": en("video,cutter,dead air,trim,editor,talking head,reels,shorts,vlog,gaps,speech,shorten,interview,ugc"),
    "en-CA": en("video,cutter,dead air,trim,editor,talking head,reels,shorts,vlog,gaps,speech,lecture,shorten,clip"),
}

data["tr"] = {
    "description": """Konuşmalı videolarındaki sessizlikleri otomatik olarak sil. CutSense klibindeki uzun duraklamaları ve boş anları bulur, iPhone'unda keser; videon lafı uzatmadan konuya girer.

NASIL ÇALIŞIR
1. Fotoğraflar'dan bir video seç.
2. Bir stil seç: Dengeli (önerilen), Sıkı veya Hardcore.
3. Sonucu önizle, ne kadarının kesildiğini gör.
4. "Kesimleri incele"yi aç, istediğin duraklamayı geri al.
5. Fotoğraflar'a kaydet ya da paylaş.

HER KESİMİ İNCELE
Kesilen her duraklama tek tek listelenir. Bir espriden önceki kısa bekleyiş ya da iki fikir arasındaki nefes gibi önemli olanları tut, gerisini kes. Kesimleri tek tek değiştir. Ücretsiz sürüm video başına 3 duraklamaya kadar tutar. Pro'da istediğin kadarını tutarsın, ayrıca "Tümünü tut" açılır. Kaydedene kadar hiçbir şey kesinleşmez.

İÇERİK ÜRETİCİLERİ NEDEN KULLANIYOR
- Elle kırpmadan daha akıcı Reels ve Shorts
- Vlog, eğitim, röportaj ve kameraya konuşma videoları için jump cut temposu
- Ders kayıtları, UGC ve ürün videolarında daha hızlı kurgu
- Videolarında filigran yok
- Hesap ya da üyelik gerekmez

GİZLİLİK ÖNCELİKLİ
Videon cihazında işlenir ve hiçbir yere yüklenmez. Orijinal dosyan olduğu gibi kalır. CutSense sonucu yeni bir MP4 olarak oluşturur; Fotoğraflar'a kaydedebilir ya da paylaşabilirsin.

CUTSENSE PRO
İsteğe bağlı, tek seferlik satın alma. Abonelik yok. Pro tüm reklamları kalıcı olarak kaldırır, istediğin kadar duraklamayı tutmanı sağlar ve İnce ayar'ı açar: en kısa duraklama süresini ve konuşmanın etrafında kalacak nefes payını sen belirlersin.

BİLMENDE FAYDA VAR
- CutSense sessizlikleri siler. "Eee", "ııı" gibi dolgu sözcüklerini silmez, en iyi çekimini de senin yerine seçmez.
- En iyi sonucu net konuşmada verir. Az konuşma olan videolarda kesilen kısım çok olur; uygulama bu durumda seni uyarır.

CutSense ücretsizdir ve reklamlarla desteklenir. İstersen kısa bir reklam izleyip 24 saat banner reklam görmeden kullanabilirsin. Uygulama Türkçe, İngilizce, İspanyolca, Portekizce, Almanca, Fransızca, İtalyanca, Japonca ve Korece kullanılabilir.""",
    "promotionalText": "Konuşmalı videolarındaki ölü anları at. Ücretsiz, filigransız; videon iPhone'undan hiç çıkmaz.",
    "whatsNew": """1.1.0 ile gelenler
- Kaydetmeden önce önizleme: sonucu izle, ne kadarının kesildiğini gör.
- Her kesimi incele, istediğin duraklamayı geri al.
- Varsayılan artık Dengeli; videoların gereğinden fazla kesilmez.
- Az konuşma olan videolar için uyarı.
- CutSense Pro: abonelik yok, tek seferlik satın alma. Reklamları kaldırır, sınırsız duraklama tutar ve İnce ayar'ı açar.
- Uygulama artık 9 dilde.
- Geçici dosyalar otomatik temizlenir; Ayarlar kullanılan depolama alanını gösterir.
- Kararlılık düzeltmeleri.""",
    "keywords": "video kesme,boşluk,kırpma,düzenleme,reels,shorts,vlog,silici,konuşma,ölü an,kısaltma,röportaj,ders",
}

data["es-ES"] = {
    "description": """Elimina los silencios de cualquier vídeo hablado. CutSense encuentra las pausas largas y los tiempos muertos de tu clip y los corta en tu iPhone, para que tu vídeo vaya al grano.

CÓMO FUNCIONA
1. Elige un vídeo de Fotos.
2. Escoge un estilo: Equilibrado (recomendado), Ajustado o Extremo.
3. Previsualiza el resultado y mira cuánto se ha quitado.
4. Abre Ver cortes y conserva las pausas que quieras.
5. Guarda en Fotos o comparte.

REVISA CADA CORTE
Cada pausa eliminada aparece en una lista. Conserva las que importan, como un silencio antes del remate o una respiración entre dos ideas, y corta el resto. Cambia los cortes uno a uno. La versión gratuita conserva hasta 3 pausas por vídeo. Pro conserva todas las que quieras y añade Mantener todo. Nada es definitivo hasta que guardas.

POR QUÉ LO USAN LOS CREADORES
- Reels y Shorts más dinámicos sin recortar a mano
- Ritmo de jump cut para vlogs, tutoriales, entrevistas y vídeos a cámara
- Ediciones más rápidas de clases, UGC y vídeos de producto
- Sin marca de agua en tus vídeos
- Sin cuenta ni registro

PRIVADO DE SERIE
Tu vídeo se procesa en tu dispositivo y nunca se sube. El original queda intacto. CutSense guarda el resultado como un MP4 nuevo que puedes guardar en Fotos o compartir.

CUTSENSE PRO
Una compra única y opcional. Sin suscripción. Pro elimina todos los anuncios para siempre, te deja conservar todas las pausas que quieras y desbloquea Ajuste fino, donde eliges la duración mínima de pausa y el margen que queda alrededor de tus palabras.

BUENO SABERLO
- CutSense elimina silencios. No quita muletillas como "eh" ni elige tus mejores tomas.
- Funciona mejor con voz clara. Si un vídeo tiene poca voz, se cortará mucho, y la app te avisa cuando pasa.

CutSense es gratis y se financia con anuncios. Si quieres, mira un anuncio breve y disfruta 24 horas sin banners. La app está disponible en español, inglés, turco, portugués, alemán, francés, italiano, japonés y coreano.""",
    "promotionalText": "Quita los tiempos muertos de tus vídeos hablados. Gratis, sin marca de agua y tu vídeo nunca sale de tu iPhone.",
    "whatsNew": """Novedades de la 1.1.0
- Vista previa antes de guardar: mira el resultado y cuánto se ha quitado.
- Revisa cada corte y conserva las pausas que quieras.
- Equilibrado es el nuevo estilo por defecto, para no cortar de más.
- Aviso cuando un vídeo tiene poca voz.
- CutSense Pro: compra única, sin suscripción. Elimina los anuncios, conserva pausas sin límite y desbloquea Ajuste fino.
- La app ya está en 9 idiomas.
- Los archivos temporales se borran solos y Ajustes muestra el espacio usado.
- Mejoras de estabilidad.""",
    "keywords": "cortar,vídeo,editor,recortar,reels,shorts,vlog,huecos,tiempos muertos,acortar,entrevista,tutorial",
}

data["es-MX"] = {
    "description": """Quita los silencios de cualquier video hablado. CutSense encuentra las pausas largas y los tiempos muertos de tu clip y los corta en tu iPhone, para que tu video vaya directo al punto.

CÓMO FUNCIONA
1. Elige un video de Fotos.
2. Escoge un estilo: Equilibrado (recomendado), Ajustado o Extremo.
3. Previsualiza el resultado y ve cuánto se quitó.
4. Abre Ver cortes y conserva las pausas que quieras.
5. Guarda en Fotos o comparte.

REVISA CADA CORTE
Cada pausa eliminada aparece en una lista. Conserva las que importan, como un silencio antes del chiste o una respiración entre dos ideas, y corta el resto. Cambia los cortes uno por uno. La versión gratuita conserva hasta 3 pausas por video. Pro conserva todas las que quieras y agrega Mantener todo. Nada es definitivo hasta que guardas.

POR QUÉ LO USAN LOS CREADORES
- Reels y Shorts más ágiles sin recortar a mano
- Ritmo de jump cut para vlogs, tutoriales, entrevistas y videos a cámara
- Ediciones más rápidas de clases, UGC y videos de producto
- Sin marca de agua en tus videos
- Sin cuenta ni registro

PRIVADO DESDE EL DISEÑO
Tu video se procesa en tu dispositivo y nunca se sube. El original queda intacto. CutSense guarda el resultado como un MP4 nuevo que puedes guardar en Fotos o compartir.

CUTSENSE PRO
Una compra única y opcional. Sin suscripción. Pro quita todos los anuncios para siempre, te deja conservar todas las pausas que quieras y desbloquea Ajuste fino, donde eliges la duración mínima de pausa y el margen que queda alrededor de tus palabras.

QUÉ DEBES SABER
- CutSense quita silencios. No elimina muletillas como "este" o "eh" ni elige tus mejores tomas.
- Funciona mejor con voz clara. Si un video tiene poca voz, se cortará mucho, y la app te avisa cuando pasa.

CutSense es gratis y se mantiene con anuncios. Si quieres, ve un anuncio corto y disfruta 24 horas sin banners. La app está disponible en español, inglés, turco, portugués, alemán, francés, italiano, japonés y coreano.""",
    "promotionalText": "Saca los tiempos muertos de tus videos hablados. Gratis, sin marca de agua y tu video nunca sale de tu iPhone.",
    "whatsNew": """Novedades de la 1.1.0
- Vista previa antes de guardar: ve el resultado y cuánto se quitó.
- Revisa cada corte y conserva las pausas que quieras.
- Equilibrado es el nuevo estilo predeterminado, para no cortar de más.
- Aviso cuando un video tiene poca voz.
- CutSense Pro: compra única, sin suscripción. Quita los anuncios, conserva pausas sin límite y desbloquea Ajuste fino.
- La app ya está en 9 idiomas.
- Los archivos temporales se borran solos y Ajustes muestra el espacio usado.
- Mejoras de estabilidad.""",
    "keywords": "trimmer,shorten,clip,speech,lecture,cortar,recortar,editor,reels,shorts,vlog,video,huecos,entrevista",
}

data["pt-BR"] = {
    "description": """Remova o silêncio de qualquer vídeo falado. O CutSense encontra as pausas longas e os tempos mortos do seu clipe e corta tudo no seu iPhone, para o seu vídeo ir direto ao ponto.

COMO FUNCIONA
1. Escolha um vídeo em Fotos.
2. Escolha um estilo: Equilibrado (recomendado), Intenso ou Extremo.
3. Veja a prévia do resultado e quanto foi removido.
4. Abra Ver cortes e mantenha as pausas que quiser.
5. Salve em Fotos ou compartilhe.

REVISE CADA CORTE
Cada pausa removida aparece em uma lista. Mantenha as que importam, como uma pausa antes da piada ou um respiro entre duas ideias, e corte o resto. Altere os cortes um a um. A versão gratuita mantém até 3 pausas por vídeo. O Pro mantém quantas você quiser e libera o Manter tudo. Nada é definitivo até você salvar.

POR QUE CRIADORES USAM
- Reels e Shorts mais dinâmicos sem aparar na mão
- Ritmo de jump cut para vlogs, tutoriais, entrevistas e vídeos falando para a câmera
- Edição mais rápida de aulas, UGC e vídeos de produto
- Sem marca d'água nos seus vídeos
- Sem conta e sem cadastro

PRIVADO POR PADRÃO
Seu vídeo é processado no seu aparelho e nunca é enviado. O original fica intacto. O CutSense salva o resultado como um novo MP4 que você pode guardar em Fotos ou compartilhar.

CUTSENSE PRO
Uma compra única e opcional. Sem assinatura. O Pro remove todos os anúncios para sempre, deixa você manter quantas pausas quiser e libera o Ajuste fino, onde você define a duração mínima da pausa e o respiro que fica em volta da sua fala.

BOM SABER
- O CutSense remove silêncio. Ele não remove vícios de linguagem como "é..." ou "tipo" e não escolhe suas melhores tomadas.
- Funciona melhor com fala clara. Se um vídeo tiver pouca fala, muita coisa será cortada, e o app avisa quando isso acontece.

O CutSense é gratuito e mantido por anúncios. Se quiser, assista a um anúncio curto e fique 24 horas sem banners. O app está disponível em português, inglês, turco, espanhol, alemão, francês, italiano, japonês e coreano.""",
    "promotionalText": "Tire o tempo morto dos seus vídeos falados. Grátis, sem marca d'água e seu vídeo nunca sai do seu iPhone.",
    "whatsNew": """Novidades da 1.1.0
- Prévia antes de salvar: veja o resultado e quanto foi removido.
- Revise cada corte e mantenha as pausas que quiser.
- Equilibrado é o novo padrão, para não cortar demais.
- Aviso quando um vídeo tem pouca fala.
- CutSense Pro: compra única, sem assinatura. Remove os anúncios, mantém pausas sem limite e libera o Ajuste fino.
- O app agora está em 9 idiomas.
- Arquivos temporários são apagados automaticamente e os Ajustes mostram o espaço usado.
- Correções de estabilidade.""",
    "keywords": "vídeo,editor,aparar,encurtar,tirar,reels,shorts,vlog,tempo morto,fala,entrevista,tutorial,ugc,edição",
}

data["de-DE"] = {
    "description": """Entferne Stille aus jedem Video, in dem gesprochen wird. CutSense findet lange Pausen und Leerlauf in deinem Clip und schneidet sie direkt auf deinem iPhone heraus, damit dein Video schneller auf den Punkt kommt.

SO FUNKTIONIERT'S
1. Wähle ein Video aus Fotos.
2. Wähle einen Stil: Ausgewogen (empfohlen), Straff oder Extrem.
3. Sieh dir das Ergebnis in der Vorschau an und wie viel entfernt wurde.
4. Öffne Schnitte und behalte jede Pause, die du willst.
5. In Fotos sichern oder teilen.

JEDEN SCHNITT PRÜFEN
Jede entfernte Pause wird aufgelistet. Behalte die wichtigen, etwa einen Moment vor der Pointe oder ein Atemholen zwischen zwei Gedanken, und schneide den Rest. Ändere Schnitte einzeln. Die kostenlose Version behält bis zu 3 Pausen pro Video. Mit Pro behältst du so viele, wie du willst, und bekommst Alle behalten dazu. Erst beim Sichern wird etwas endgültig.

WARUM CREATOR ES NUTZEN
- Knackigere Reels und Shorts ohne Handarbeit beim Trimmen
- Jump-Cut-Tempo für Vlogs, Tutorials, Interviews und Talking-Head-Videos
- Schnellere Bearbeitung von Vorlesungen, UGC und Produktvideos
- Kein Wasserzeichen in deinen Videos
- Kein Konto, keine Registrierung

PRIVAT VON ANFANG AN
Dein Video wird auf deinem Gerät verarbeitet und nie hochgeladen. Das Original bleibt unverändert. CutSense speichert das Ergebnis als neue MP4, die du in Fotos sichern oder teilen kannst.

CUTSENSE PRO
Ein optionaler Einmalkauf. Kein Abo. Pro entfernt alle Werbung dauerhaft, lässt dich so viele Pausen behalten, wie du willst, und schaltet Feinschliff frei: Dort legst du die minimale Pausenlänge und den Puffer um deine Worte fest.

GUT ZU WISSEN
- CutSense entfernt Stille. Füllwörter wie "äh" entfernt es nicht, und es wählt nicht deine besten Takes aus.
- Am besten klappt es mit klarer Sprache. Enthält ein Video wenig Sprache, wird viel geschnitten, und die App warnt dich in diesem Fall.

CutSense ist kostenlos und wird durch Werbung finanziert. Wenn du möchtest, sieh dir eine kurze Werbung an und nutze die App 24 Stunden ohne Bannerwerbung. Die App gibt es auf Deutsch, Englisch, Türkisch, Spanisch, Portugiesisch, Französisch, Italienisch, Japanisch und Koreanisch.""",
    "promotionalText": "Schluss mit Leerlauf in deinen Sprechvideos. Kostenlos, ohne Wasserzeichen, und dein Video verlässt nie dein iPhone.",
    "whatsNew": """Neu in 1.1.0
- Vorschau vor dem Sichern: Sieh dir das Ergebnis an und wie viel entfernt wurde.
- Prüfe jeden Schnitt und behalte jede Pause, die du willst.
- Ausgewogen ist der neue Standard, damit nicht zu viel geschnitten wird.
- Warnung, wenn ein Video wenig Sprache enthält.
- CutSense Pro: Einmalkauf, kein Abo. Entfernt die Werbung, behält unbegrenzt Pausen und schaltet Feinschliff frei.
- Die App gibt es jetzt in 9 Sprachen.
- Temporäre Dateien werden automatisch gelöscht, und die Einstellungen zeigen den belegten Speicher.
- Stabilitätsverbesserungen.""",
    "keywords": "video,schnitt,schneiden,kürzen,editor,vlog,reels,shorts,sprache,interview,tutorial,lücken,leerlauf",
}

data["fr-FR"] = {
    "description": """Supprimez les silences de toutes vos vidéos parlées. CutSense repère les longues pauses et les temps morts de votre clip et les coupe directement sur votre iPhone, pour que votre vidéo aille droit au but.

COMMENT ÇA MARCHE
1. Choisissez une vidéo dans Photos.
2. Choisissez un style : Équilibré (recommandé), Serré ou Extrême.
3. Prévisualisez le résultat et voyez combien de temps a été retiré.
4. Ouvrez Voir les coupes pour garder les pauses de votre choix.
5. Enregistrez dans Photos ou partagez.

VÉRIFIEZ CHAQUE COUPE
Chaque pause retirée apparaît dans une liste. Gardez celles qui comptent, comme un temps avant la chute ou une respiration entre deux idées, et coupez le reste. Modifiez les coupes une par une. La version gratuite garde jusqu'à 3 pauses par vidéo. Pro en garde autant que vous voulez et ajoute Tout garder. Rien n'est définitif avant l'enregistrement.

POURQUOI LES CRÉATEURS L'UTILISENT
- Des Reels et des Shorts plus rythmés, sans découper à la main
- Un rythme en jump cut pour les vlogs, tutoriels, interviews et vidéos face caméra
- Un montage plus rapide pour les cours, l'UGC et les vidéos produit
- Aucun filigrane sur vos vidéos
- Aucun compte ni inscription

CONFIDENTIEL PAR NATURE
Votre vidéo est traitée sur votre appareil et n'est jamais envoyée en ligne. L'original reste intact. CutSense enregistre le résultat dans un nouveau fichier MP4, à garder dans Photos ou à partager.

CUTSENSE PRO
Un achat unique et facultatif. Sans abonnement. Pro supprime toutes les publicités pour de bon, vous laisse garder autant de pauses que vous voulez et débloque Ajuster : vous réglez la durée minimale des pauses et la marge laissée autour de vos paroles.

BON À SAVOIR
- CutSense supprime les silences. Il ne retire pas les mots de remplissage comme « euh » et ne choisit pas vos meilleures prises.
- Il fonctionne mieux avec une voix claire. Si une vidéo contient peu de parole, une grande partie sera coupée, et l'app vous prévient dans ce cas.

CutSense est gratuit et financé par la publicité. Si vous le souhaitez, regardez une courte pub pour profiter de 24 h sans bannières. L'app est disponible en français, anglais, turc, espagnol, portugais, allemand, italien, japonais et coréen.""",
    "promotionalText": "Fini les temps morts dans vos vidéos parlées. Gratuit, sans filigrane, et votre vidéo ne quitte jamais votre iPhone.",
    "whatsNew": """Nouveautés de la 1.1.0
- Aperçu avant l'enregistrement : regardez le résultat et ce qui a été retiré.
- Vérifiez chaque coupe et gardez les pauses de votre choix.
- Équilibré devient le style par défaut, pour éviter de trop couper.
- Un avertissement quand une vidéo contient peu de parole.
- CutSense Pro : achat unique, sans abonnement. Supprime les publicités, garde les pauses sans limite et débloque Ajuster.
- L'app est désormais disponible en 9 langues.
- Les fichiers temporaires sont nettoyés automatiquement et les Réglages affichent l'espace utilisé.
- Améliorations de la stabilité.""",
    "keywords": "montage,couper,raccourcir,éditeur,vidéo,vlog,reels,shorts,blancs,temps mort,parole,interview,cours",
}

data["it"] = {
    "description": """Elimina i silenzi da qualsiasi video parlato. CutSense trova le pause lunghe e i tempi morti nel tuo clip e li taglia direttamente sul tuo iPhone, così il tuo video arriva subito al punto.

COME FUNZIONA
1. Scegli un video da Foto.
2. Scegli uno stile: Bilanciato (consigliato), Deciso o Estremo.
3. Guarda l'anteprima del risultato e quanto è stato tolto.
4. Apri Vedi tagli e tieni le pause che vuoi.
5. Salva in Foto o condividi.

CONTROLLA OGNI TAGLIO
Ogni pausa rimossa compare in un elenco. Tieni quelle che contano, come un attimo prima della battuta o un respiro tra due idee, e taglia il resto. Modifica i tagli uno per uno. La versione gratuita tiene fino a 3 pause per video. Pro ne tiene quante vuoi e aggiunge Tieni tutto. Niente è definitivo finché non salvi.

PERCHÉ I CREATOR LO USANO
- Reels e Shorts più incisivi senza tagliare a mano
- Ritmo jump cut per vlog, tutorial, interviste e video in camera
- Montaggio più rapido per lezioni, UGC e video prodotto
- Nessuna filigrana sui tuoi video
- Nessun account, nessuna registrazione

PRIVATO PER SCELTA
Il tuo video viene elaborato sul dispositivo e non viene mai caricato. L'originale resta intatto. CutSense salva il risultato come nuovo MP4, da tenere in Foto o condividere.

CUTSENSE PRO
Un acquisto unico e facoltativo. Nessun abbonamento. Pro rimuove per sempre tutta la pubblicità, ti lascia tenere tutte le pause che vuoi e sblocca Regola, dove imposti la durata minima delle pause e il margine lasciato intorno alle tue parole.

BUONO A SAPERSI
- CutSense elimina i silenzi. Non rimuove gli intercalari come "ehm" e non sceglie le tue riprese migliori.
- Funziona meglio con un parlato chiaro. Se un video contiene poco parlato, verrà tagliato molto, e l'app ti avvisa quando succede.

CutSense è gratuito e supportato dalla pubblicità. Se vuoi, guarda un breve annuncio e usa l'app per 24 ore senza banner. L'app è disponibile in italiano, inglese, turco, spagnolo, portoghese, tedesco, francese, giapponese e coreano.""",
    "promotionalText": "Via i tempi morti dai tuoi video parlati. Gratis, senza filigrana, e il tuo video non lascia mai il tuo iPhone.",
    "whatsNew": """Novità della 1.1.0
- Anteprima prima di salvare: guarda il risultato e quanto è stato tolto.
- Controlla ogni taglio e tieni le pause che vuoi.
- Bilanciato è il nuovo stile predefinito, per non tagliare troppo.
- Un avviso quando un video contiene poco parlato.
- CutSense Pro: acquisto unico, nessun abbonamento. Rimuove la pubblicità, tiene pause senza limiti e sblocca Regola.
- L'app ora è disponibile in 9 lingue.
- I file temporanei vengono eliminati automaticamente e Impostazioni mostra lo spazio usato.
- Correzioni di stabilità.""",
    "keywords": "video,montaggio,tagliare,accorciare,editor,vlog,reels,shorts,tempi morti,parlato,intervista,tutorial",
}

data["ja"] = {
    "description": """話している動画から、無音部分を自動で取り除きます。CutSense はクリップ内の長い間や何も起きていない時間を見つけ、iPhone 上でカット。動画がテンポよく本題に入れます。

使い方
1. 写真から動画を選びます。
2. スタイルを選びます：バランス（おすすめ）、タイト、最大。
3. 結果をプレビューして、どれだけ短くなったかを確認します。
4. 「カットを確認」を開き、残したい間をそのまま残せます。
5. 写真に保存、または共有します。

すべてのカットを確認
取り除いた間はすべて一覧で表示されます。オチの前のひと呼吸や、話の区切りの間など、大事なものは残して、あとはカット。1つずつ切り替えられます。無料版では動画ごとに3つまで間を残せます。Pro なら好きなだけ残せて、「すべて残す」も使えます。保存するまでは何も確定しません。

クリエイターに選ばれる理由
- 手作業でトリミングしなくても、リールやショートがテンポよく
- Vlog、解説、インタビュー、トーク動画にジャンプカットのリズム
- 講義、UGC、商品紹介動画の編集がスピーディに
- 動画に透かしは入りません
- アカウント登録は不要

プライバシーを守る設計
動画はデバイス上で処理され、アップロードされることはありません。元の動画はそのまま残ります。結果は新しい MP4 として作成され、写真に保存したり共有したりできます。

CUTSENSE PRO
任意の買い切り購入です。サブスクリプションはありません。Pro にするとすべての広告がずっと非表示になり、間を好きなだけ残せて、「微調整」が使えるようになります。最短の間の長さと、言葉の前後に残す余白を自分で設定できます。

ご注意
- CutSense が取り除くのは無音部分です。「えー」「あの」などのつなぎ言葉は取り除かず、ベストテイクを選ぶ機能もありません。
- はっきりした話し声で最も効果を発揮します。話し声の少ない動画は大きくカットされるため、その場合はアプリが警告します。

CutSense は無料で、広告によって提供されています。短い広告を任意で見ると、24時間バナー広告なしで使えます。アプリは日本語、英語、トルコ語、スペイン語、ポルトガル語、ドイツ語、フランス語、イタリア語、韓国語に対応しています。""",
    "promotionalText": "話す動画のムダな間をすっきりカット。無料、透かしなし、動画が iPhone の外に出ることはありません。",
    "whatsNew": """バージョン 1.1.0 の新機能
- 保存前にプレビュー：結果を見て、どれだけ短くなったかを確認できます。
- すべてのカットを確認して、残したい間を残せます。
- 標準設定が「バランス」になり、切りすぎを防ぎます。
- 話し声の少ない動画では警告が出ます。
- CutSense Pro：サブスクなしの買い切り。広告を非表示にし、間を無制限に残せて、「微調整」が使えます。
- アプリが9言語に対応しました。
- 一時ファイルは自動で削除され、設定で使用中のストレージを確認できます。
- 安定性を改善しました。""",
    "keywords": "動画編集,トリミング,短縮,空白,ムダ,トーク,Vlog,リール,ショート,解説,講義,インタビュー,話し声,UGC,クリップ,テンポ,縦動画,喋り,セミナー,会話",
}

data["ko"] = {
    "description": """말하는 영상에서 무음 구간을 자동으로 없애 줍니다. CutSense가 클립 속 긴 멈춤과 빈 시간을 찾아 iPhone에서 바로 잘라 내니, 영상이 군더더기 없이 본론으로 들어갑니다.

사용 방법
1. 사진에서 영상을 고릅니다.
2. 스타일을 고릅니다: 균형(추천), 타이트, 최대.
3. 결과를 미리 보고 얼마나 줄었는지 확인합니다.
4. '컷 확인'을 열어 남기고 싶은 멈춤은 그대로 둡니다.
5. 사진에 저장하거나 공유합니다.

모든 컷을 직접 확인
잘라 낸 멈춤은 모두 목록으로 보여 줍니다. 펀치라인 직전의 짧은 틈이나 생각 사이의 숨 고르기처럼 중요한 부분은 남기고 나머지는 자르세요. 컷을 하나씩 바꿀 수 있습니다. 무료 버전은 영상당 최대 3개의 멈춤을 유지합니다. Pro에서는 원하는 만큼 유지할 수 있고 '모두 유지'도 열립니다. 저장하기 전까지는 아무것도 확정되지 않습니다.

크리에이터가 쓰는 이유
- 손으로 다듬지 않아도 더 짜임새 있는 릴스와 쇼츠
- 브이로그, 튜토리얼, 인터뷰, 토킹헤드 영상에 점프컷 리듬
- 강의, UGC, 제품 영상 편집이 더 빠르게
- 영상에 워터마크 없음
- 계정이나 가입 필요 없음

처음부터 프라이버시 중심
영상은 기기에서 처리되며 업로드되지 않습니다. 원본은 그대로 남습니다. 결과는 새 MP4 파일로 만들어지며, 사진에 저장하거나 공유할 수 있습니다.

CUTSENSE PRO
선택 사항인 1회 구매입니다. 구독이 아닙니다. Pro는 모든 광고를 영구히 없애고, 멈춤을 원하는 만큼 유지하게 해 주며, '세부 조정'을 열어 줍니다. 최소 멈춤 길이와 말 앞뒤에 남길 여유를 직접 정할 수 있습니다.

알아 두세요
- CutSense는 무음 구간을 없앱니다. '음', '어' 같은 군말은 지우지 않으며, 가장 좋은 테이크를 골라 주지도 않습니다.
- 또렷한 말소리에서 가장 잘 작동합니다. 말소리가 적은 영상은 많이 잘릴 수 있으며, 이 경우 앱이 미리 알려 줍니다.

CutSense는 무료이며 광고로 운영됩니다. 원하면 짧은 광고를 보고 24시간 동안 배너 광고 없이 사용할 수 있습니다. 앱은 한국어, 영어, 터키어, 스페인어, 포르투갈어, 독일어, 프랑스어, 이탈리아어, 일본어를 지원합니다.""",
    "promotionalText": "말하는 영상의 빈 시간을 깔끔하게 잘라 내세요. 무료, 워터마크 없음, 영상은 iPhone 밖으로 나가지 않습니다.",
    "whatsNew": """1.1.0 새로운 기능
- 저장 전 미리 보기: 결과를 보고 얼마나 줄었는지 확인하세요.
- 모든 컷을 확인하고 원하는 멈춤은 남길 수 있습니다.
- 기본값이 '균형'으로 바뀌어 과하게 잘리지 않습니다.
- 말소리가 적은 영상에는 경고가 표시됩니다.
- CutSense Pro: 구독 없는 1회 구매. 광고를 없애고, 멈춤을 무제한 유지하며, '세부 조정'을 열어 줍니다.
- 앱이 이제 9개 언어를 지원합니다.
- 임시 파일은 자동으로 정리되며, 설정에서 사용 중인 저장 공간을 볼 수 있습니다.
- 안정성 개선.""",
    "keywords": "영상편집,동영상,자르기,트리밍,편집기,브이로그,릴스,쇼츠,강의,인터뷰,튜토리얼,토크,말하기,세로영상,말소리,발표,UGC,클립,줄이기,빈시간",
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("wrote", OUT)
