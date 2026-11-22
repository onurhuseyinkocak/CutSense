"use client";

import { useLanguage } from "../language-context";
import { SiteFooter, SiteNav } from "../site-chrome";

const contact = "info@vibecodingturkey.com";
// Seller name exactly as Apple publishes it on the App Store listing.
const seller = "Onur Hseyin Kocak";

export function PrivacyContent() {
  const { t } = useLanguage();

  const sections: { title: string; body: string[] }[] = [
    {
      title: t("Yürürlük tarihi", "Effective date"),
      body: [t("22 Kasım 2026", "November 22, 2026")],
    },
    {
      title: t("Kısaca", "Summary"),
      body: [
        t(
          "CutSense videolarını iPhone'unda işler ve onları bize ya da başka birine göndermez. Hesap, kendi sunucumuz veya analiz aracımız yok. Ücretsiz sürüm Google AdMob reklamları gösterir; Google reklam göstermek ve ölçmek için cihaz ve kullanım verilerini işler. Bu sayfa hangi verilerin, neden ve kimin tarafından işlendiğini ve bunları nasıl kontrol edeceğini anlatır.",
          "CutSense processes your videos on your iPhone and does not send them to us or anyone else. There is no account, no server of our own, and no analytics tool. The free version shows Google AdMob ads, and Google processes device and usage data to show and measure them. This page explains what data is handled, why, by whom, and how you control it.",
        ),
      ],
    },
    {
      title: t("Biz kimiz (veri sorumlusu)", "Who we are (data controller)"),
      body: [
        t(
          `CutSense, App Store'da satıcı olarak görünen ${seller} tarafından Türkiye'den yayınlanan bağımsız bir uygulamadır ("biz"). Bu politikada anlatılan, bizim karar verdiğimiz işlemler için veri sorumlusu ${seller}'tır. Gizlilikle ilgili tüm sorular ve talepler için: ${contact}.`,
          `CutSense is an independent app published from Türkiye by ${seller}, the seller listed on the App Store ("we", "us"). ${seller} is the data controller for the processing we decide on, as described in this policy. For any privacy question or request, contact ${contact}.`,
        ),
        t(
          "Google, reklam verilerini kendi amaçları için kendi veri sorumluluğunda işler (aşağıya bak). Apple, satın alımları ve App Store hesabını kendi politikasıyla işler.",
          "Google processes advertising data for its own purposes as an independent controller (see below). Apple processes purchases and your App Store account under its own policy.",
        ),
      ],
    },
    {
      title: t("Videoların cihazında kalır", "Your videos stay on your device"),
      body: [
        t(
          "Videoları iOS'un kendi Fotoğraflar seçicisiyle seçersin. CutSense yalnızca seçtiğin videoyu alır, arşivinin geri kalanını görmez. Sessizlik analizi, kesim ve dışa aktarma tamamen iPhone'unda çalışır. Videolar, ses ve kesim sonuçları bize, Google'a veya başka bir sunucuya yüklenmez.",
          "You pick videos with the iOS Photos picker. CutSense receives only the video you pick and does not see the rest of your library. Silence analysis, cutting, and export run entirely on your iPhone. Videos, audio, and cut results are not uploaded to us, to Google, or to any other server.",
        ),
        t(
          "İşlem sırasında uygulama, cihazında geçici çalışma kopyaları oluşturur. Bunlar iş bittiğinde ve uygulamanın bir sonraki açılışında silinir; CutSense 1.1 ve sonrasında Ayarlar > Depolama > Temizle ile istediğin an silebilirsin. Fotoğraflar'a kaydettiğinde uygulama yalnızca ekleme izni ister; mevcut fotoğraflarını okuyamaz veya değiştiremez. İzinleri iOS Ayarları'ndan değiştirebilirsin.",
          "While processing, the app creates temporary working copies on your device. They are deleted when the job ends and the next time the app starts, and in CutSense 1.1 and later you can delete them any time in Settings > Storage > Clear. When you save to Photos, the app asks only for add-only permission, so it cannot read or change your existing photos. You can change permissions in iOS Settings.",
        ),
      ],
    },
    {
      title: t("Cihazında saklanan ayarlar", "Settings stored on your device"),
      body: [
        t(
          "CutSense şunları yalnızca cihazında saklar: seçtiğin dil, Pro'nun açık olup olmadığı, reklamsız sürenin bitiş zamanı, teklif zamanlayıcıları, sayaçlar (kaydettiğin video sayısı, tanıtımın ve değerlendirme isteğinin gösterilip gösterilmediği), kesim modu ve ince ayar değerleri. Geçmiş ekranı (1.1 ve sonrası), Fotoğraflar'a kaydettiğin her video için bir önizleme karesi ile birkaç sayı tutar: tarih, eski ve yeni süre, kesim oranı, kesim modu ve çözünürlük. Videonun kendisi saklanmaz.",
          "CutSense keeps the following only on your device: your chosen language, whether Pro is unlocked, when an ad-free period ends, offer timers, counters (how many videos you have saved, whether the intro and the rating prompt were shown), the cut mode, and fine-tune values. The History screen (version 1.1 and later) keeps, for each video you save to Photos, a preview frame and a few numbers: date, original and new length, how much was cut, cut mode, and resolution. The video itself is not stored.",
        ),
        t(
          "Geçmiş kayıtları iCloud yedeğine alınmaz; ayarlar cihaz yedeğine dahil olabilir. Bunların hiçbiri bize gönderilmez. Uygulamayı silince hepsi silinir.",
          "History records are excluded from iCloud backup; settings may be included in your device backup. Nothing is sent to us. Deleting the app deletes all of it.",
        ),
      ],
    },
    {
      title: t("Bizim topladığımız veriler", "Data we collect"),
      body: [
        t(
          "Uygulama üzerinden kişisel veri almıyoruz: hesap, kendi sunucumuz, analiz, çökme raporlama veya pazarlama aracı kullanmıyoruz. Apple, App Store Connect'te bize toplu indirme, satış ve (paylaşmayı seçtiysen) çökme istatistikleri gösterebilir; bunlar seni tanımlamaz.",
          "We do not receive personal data through the app: we use no account, no server of our own, and no analytics, crash-reporting, or marketing tool. Apple may show us aggregated download, sales, and (if you chose to share them) crash statistics in App Store Connect; these do not identify you.",
        ),
        t(
          "Bize e-posta yazarsan e-posta adresini ve mesajını yalnızca sana yanıt vermek için kullanırız. E-postalar, e-posta sağlayıcımız Google Workspace'te (Google LLC) saklanır. Talebin çözülünce, yasal bir zorunluluk yoksa silinir; daha önce silmemizi istersen sileriz.",
          "If you email us, we use your email address and message only to reply. Emails are stored with our email provider, Google Workspace (Google LLC). They are deleted once your request is resolved unless the law requires us to keep them, and we delete them sooner if you ask.",
        ),
      ],
    },
    {
      title: t("Reklamlar: Google AdMob", "Advertising: Google AdMob"),
      body: [
        t(
          "Ücretsiz sürüm Google Mobile Ads SDK (AdMob) ile banner reklamlar, işlem sırasında native reklamlar ve atlanabilir ödüllü reklamlar gösterir. Google'ın açıklamasına göre SDK şunları toplayabilir: IP adresi, cihaz tanımlayıcıları (uygulamaya veya geliştiriciye özel kimlikler), gördüğün reklamlar gibi reklam verileri, uygulama açılışı ve reklam etkileşimleri gibi ürün etkileşimleri, IP adresinden çıkarılan yaklaşık konum, çökme ve performans verileri.",
          "The free version uses the Google Mobile Ads SDK (AdMob) to show banner ads, native ads while a video is processing, and skippable rewarded ads. According to Google, the SDK may collect: IP address, device identifiers (app- or developer-scoped IDs), advertising data such as ads you have seen, product interactions such as app launches and ad taps, approximate location derived from your IP address, and crash and performance data.",
        ),
        t(
          "Google bu verileri reklam göstermek ve seçmek, reklam performansını ölçmek, reklam sıklığını sınırlamak, dolandırıcılığı ve kötüye kullanımı önlemek ve hizmetini iyileştirmek için kullanır. Google'ın rıza formunun gösterildiği bölgelerde (AEA, Birleşik Krallık, İsviçre) kişiselleştirilmiş reklam yalnızca verdiğin izinle gösterilir. CutSense 1.1 ve sonrasında Türkiye'de reklamlar kişiselleştirilmemiş olarak istenir. Google bu verileri kendi gizlilik politikasına göre bağımsız olarak işler: policies.google.com/privacy ve policies.google.com/technologies/partner-sites.",
          "Google uses this data to serve and select ads, measure ad performance, limit how often you see an ad, prevent fraud and abuse, and improve its service. In regions where Google's consent form is shown (EEA, UK, Switzerland), personalized ads are shown only with your consent. In CutSense 1.1 and later, ads in Türkiye are requested as non-personalized. Google processes this data independently under its own privacy policy: policies.google.com/privacy and policies.google.com/technologies/partner-sites.",
        ),
        t(
          "Google bu verileri kendi gizlilik politikası ve AdMob şartları kapsamında işler. Reklam için Google dışında hiçbir üçüncü tarafla çalışmayız; destek e-postaları yalnızca e-posta sağlayıcımızda bulunur. Pro sahiplerine reklam gösterilmez; reklam SDK'sı satın almadan sonraki açılıştan itibaren hiç başlatılmaz.",
          "Google processes this data under its own privacy policy and the AdMob terms. We work with no third party for ads other than Google; support emails are held only by our email provider. Pro owners see no ads, and the ad SDK is not started from the next launch after purchase.",
        ),
      ],
    },
    {
      title: t("Takip ve IDFA", "Tracking and IDFA"),
      body: [
        t(
          "CutSense App Tracking Transparency izni istemez, bu yüzden reklam kimliğine (IDFA) erişilmez ve verilerin başka şirketlerin uygulama veya sitelerindeki verilerle eşleştirilerek seni takip etmek için kullanılmaz. Google yukarıda anlatılan verileri yine de işleyebilir.",
          "CutSense does not ask for App Tracking Transparency permission, so the advertising identifier (IDFA) is not accessed and your data is not linked with data from other companies' apps or websites to track you. Google may still process the data described above.",
        ),
      ],
    },
    {
      title: t("AEA, Birleşik Krallık ve İsviçre (GDPR / UK GDPR)", "EEA, UK, and Switzerland (GDPR / UK GDPR)"),
      body: [
        t(
          "Bu bölgelerde CutSense ilk açılışta Google'ın rıza formunu (User Messaging Platform) gösterir. Cihazında bilgi saklanması veya okunması ve kişiselleştirilmiş reklam için hukuki dayanak rızandır (GDPR / UK GDPR md. 6(1)(a)). Rıza vermezsen Google, yasanın izin verdiği ölçüde sınırlı veya kişiselleştirilmemiş reklam gösterebilir; dolandırıcılık önleme ve güvenlik gibi amaçlar için meşru menfaate dayanabilir. Satın alımlar sözleşmenin ifasına, destek yazışmaları meşru menfaatimize dayanır.",
          "In these regions CutSense shows Google's consent form (User Messaging Platform) on first launch. The legal basis for storing or reading information on your device and for personalized ads is your consent (GDPR / UK GDPR Art. 6(1)(a)). If you do not consent, Google may show limited or non-personalized ads where the law allows and may rely on legitimate interests for purposes such as fraud prevention and security. Purchases rely on performance of a contract, and support emails on our legitimate interest in answering you.",
        ),
        t(
          "Rızanı istediğin an geri çekebilir veya değiştirebilirsin: uygulamada Ayarlar > Reklam gizliliği > Gizlilik tercihlerini yönet (CutSense 1.1 ve sonrası). Bu satır, bölgende gerekli olduğunda ve reklamlar açıkken görünür. Geri çekmek, önceki işlemenin hukuka uygunluğunu etkilemez.",
          "You can withdraw or change consent at any time in the app: Settings > Ad privacy > Manage privacy choices (CutSense 1.1 and later). This row appears where it is required in your region and while ads are on. Withdrawing does not affect processing that happened before.",
        ),
        t(
          "Bu bölgelerdeki hakların: verilerine erişim, düzeltme, silme, işlemenin kısıtlanması, itiraz (meşru menfaate dayanan işlemeye ve doğrudan pazarlamaya), veri taşınabilirliği ve rızayı geri çekme. Yalnızca otomatik işlemeye dayanan ve seni önemli ölçüde etkileyen bir karar almayız. Talebini e-postayla ilet; 30 gün içinde yanıt veririz.",
          "Your rights in these regions: access, correction, deletion, restriction of processing, objection (to processing based on legitimate interests and to direct marketing), data portability, and withdrawal of consent. We make no decisions based solely on automated processing that significantly affect you. Email us with your request and we will reply within 30 days.",
        ),
        t(
          "Yaşadığın, çalıştığın veya ihlalin gerçekleştiği yerdeki veri koruma otoritesine şikâyet etme hakkın vardır; Birleşik Krallık'ta bu otorite ICO'dur (ico.org.uk). Önce bize yazarsan sorunu birlikte çözmeye çalışırız.",
          "You have the right to complain to the data protection authority where you live, work, or where an infringement happened; in the UK this is the ICO (ico.org.uk). If you contact us first, we will try to resolve it with you.",
        ),
      ],
    },
    {
      title: t("Türkiye: KVKK aydınlatma metni", "Türkiye: KVKK notice"),
      body: [
        t(
          `6698 sayılı Kişisel Verilerin Korunması Kanunu (KVKK) md. 10 kapsamında aydınlatma. Veri sorumlusu: ${seller}, Türkiye. E-posta: ${contact}.`,
          `Notice under Türkiye's Personal Data Protection Law No. 6698 (KVKK), Art. 10. Data controller: ${seller}, Türkiye. Email: ${contact}.`,
        ),
        t(
          "İşlenen veriler, amaçlar ve toplama yöntemi: (1) Bize yazarsan e-posta adresin ve mesajın; yalnızca talebini yanıtlamak için, senin gönderdiğin e-postayla. (2) Ücretsiz sürümde IP adresi, cihaz tanımlayıcıları, reklam ve etkileşim verileri, yaklaşık konum, çökme ve performans verileri; reklam göstermek, ölçmek ve dolandırıcılığı önlemek için. Bu verileri Google, Google Mobile Ads SDK aracılığıyla otomatik yollarla doğrudan cihazından ve kendi veri sorumluluğunda toplar. CutSense 1.1 ve sonrasında Türkiye'de reklamlar kişiselleştirilmemiş olarak istenir. Biz bu verileri görmeyiz ve saklamayız. Videoların ve Geçmiş kayıtların cihazından çıkmaz ve bize ulaşmaz.",
          "Data, purposes, and collection method: (1) If you email us, your email address and message, only to answer your request, collected through the email you send. (2) In the free version, the IP address, device identifiers, advertising and interaction data, approximate location, and crash and performance data, to show and measure ads and prevent fraud. Google collects this data automatically, directly from your device through the Google Mobile Ads SDK, under its own controller responsibility. In CutSense 1.1 and later, ads in Türkiye are requested as non-personalized. We do not see or store this data. Your videos and History entries never leave your device and never reach us.",
        ),
        t(
          "Hukuki sebepler: destek yazışmaları için meşru menfaatimiz (md. 5/2-f); satın alımla ilgili sorular için bir sözleşmenin kurulması veya ifası (md. 5/2-c); ücretsiz sürümün reklamla sunulması için meşru menfaatimiz (md. 5/2-f). Google'ın reklam ayarlarını myadcenter.google.com adresinden yönetebilir veya sunulduğu yerde CutSense Pro ile reklamları tamamen kaldırabilirsin.",
          "Legal grounds: our legitimate interest for support emails (Art. 5/2-f); establishing or performing a contract for purchase questions (Art. 5/2-c); our legitimate interest in offering the free version with ads (Art. 5/2-f). You can manage Google's ad settings at myadcenter.google.com, or, where available, remove ads entirely with CutSense Pro.",
        ),
        t(
          "Yurt dışı: Google (Google LLC ve bağlı şirketleri) reklam verilerini doğrudan cihazından kendi veri sorumluluğunda toplar ve ABD dahil yurt dışında işleyebilir; bu veriler bize gelmez. Destek e-postaları, e-posta sağlayıcımız Google Workspace'in (Google LLC) yurt dışındaki sunucularında saklanır. Bu aktarım, e-postayı kendi isteğinle göndermene ve talebini yanıtlamak için zorunlu olmasına dayanır (KVKK md. 9). Verilerini başka hiçbir üçüncü kişiye aktarmayız veya satmayız.",
          "Abroad: Google (Google LLC and its affiliates) collects advertising data directly from your device under its own controller responsibility and may process it outside Türkiye, including in the United States; this data does not reach us. Support emails are stored on servers of our email provider, Google Workspace (Google LLC), outside Türkiye. That transfer relies on your own request in sending the email and on it being necessary to answer you (KVKK Art. 9). We do not transfer or sell your data to anyone else.",
        ),
        t(
          "KVKK md. 11 uyarınca hakların: kişisel verinin işlenip işlenmediğini öğrenme; işlenmişse bilgi talep etme; işlenme amacını ve amacına uygun kullanılıp kullanılmadığını öğrenme; yurt içinde veya yurt dışında aktarıldığı üçüncü kişileri bilme; eksik veya yanlış işlenmişse düzeltilmesini isteme; md. 7 şartları çerçevesinde silinmesini veya yok edilmesini isteme; düzeltme ve silme işlemlerinin aktarılan üçüncü kişilere bildirilmesini isteme; münhasıran otomatik sistemlerle analiz edilmesi sonucu aleyhine bir sonuç çıkmasına itiraz etme; kanuna aykırı işleme nedeniyle zarara uğrarsan zararın giderilmesini talep etme.",
          "Your rights under KVKK Art. 11: to learn whether your personal data is processed; to request information if it is; to learn the purpose and whether it is used accordingly; to know the third parties it is transferred to in Türkiye or abroad; to request correction of incomplete or inaccurate data; to request deletion or destruction under Art. 7; to request that corrections and deletions be notified to those third parties; to object to an outcome against you resulting solely from automated analysis; and to claim compensation for damage caused by unlawful processing.",
        ),
        t(
          `Başvuru yolu: kimliğini ve talebini açıkça belirterek ${contact} adresine yazılı (e-posta) olarak ilet. Talebini en kısa sürede ve en geç 30 gün içinde ücretsiz sonuçlandırırız (md. 13). Başvurun reddedilirse, yanıtı yetersiz bulursan veya süresinde yanıt alamazsan, yanıtı öğrendiğin tarihten itibaren 30 gün ve her hâlde başvuru tarihinden itibaren 60 gün içinde Kişisel Verileri Koruma Kurulu'na şikâyette bulunabilirsin (md. 14, kvkk.gov.tr). Google'ın tuttuğu reklam verileri için Google'ın araçlarını da kullanabilirsin.`,
          `How to apply: email ${contact} in writing, stating who you are and what you are asking for. We will resolve your request as soon as possible and within 30 days at the latest, free of charge (Art. 13). If your request is refused, you find the answer insufficient, or you get no answer in time, you can complain to the Personal Data Protection Board within 30 days of learning of the answer and in any case within 60 days of your application (Art. 14, kvkk.gov.tr). For advertising data held by Google, you can also use Google's own tools.`,
        ),
      ],
    },
    {
      title: t("ABD eyalet gizlilik hakları", "US state privacy rights"),
      body: [
        t(
          "CutSense kişisel bilgileri para karşılığı satmaz. Google ücretsiz sürümdeki reklam verilerini hedefli reklam için kullanabilir; California (CCPA/CPRA) gibi bazı ABD eyalet yasaları bunu \"paylaşma\" sayar. İlgili kategoriler: tanımlayıcılar, internet veya ağ etkinliği (reklam etkileşimleri) ve yaklaşık konum. Hassas kişisel bilgi (kesin konum, sağlık, finansal hesap, kimlik numarası gibi) toplamayız, satmayız ve paylaşmayız.",
          "CutSense does not sell personal information for money. Google may use ad data from the free version for targeted advertising, which some US state laws, such as California's (CCPA/CPRA), treat as \"sharing\". The categories involved are identifiers, internet or network activity (ad interactions), and approximate location. We do not collect, sell, or share sensitive personal information (such as precise location, health, financial account, or government ID data).",
        ),
        t(
          "CutSense takip izni (App Tracking Transparency) istemediği için reklam kimliği (IDFA) kullanılmaz. Hedefli reklamı sınırlamak için Google reklam ayarlarını adssettings.google.com veya myadcenter.google.com adresinden yönet ya da sunulduğu yerde CutSense Pro ile reklamları tamamen kapat. Tarayıcı kaynaklı Global Privacy Control sinyalleri bu uygulamaya ulaşmaz. Seninle ilişkilendirilmiş bir veri tutmadığımız için talebi senin yerine Google'a uygulayamayız; hakkını kullandığın için sana farklı davranmayız.",
          "CutSense does not ask for App Tracking Transparency permission, so the advertising identifier (IDFA) is not used. To limit targeted ads, manage Google's ad settings at adssettings.google.com or myadcenter.google.com, or turn ads off completely with CutSense Pro where available. Browser Global Privacy Control signals do not reach this app. Because we hold no data linked to you, we cannot apply an opt-out at Google on your behalf, and we will not treat you differently for using your rights.",
        ),
      ],
    },
    {
      title: t("Satın alımlar", "Purchases"),
      body: [
        t(
          "Uygulamada sunulduğu yerde CutSense Pro, Apple'ın App Store'u üzerinden satılan tek seferlik bir uygulama içi satın alımdır. Ödemeyi Apple işler. Kart bilgilerini, adını, e-postanı veya Apple Kimliğini almayız. Uygulama, Pro'nun açık olup olmadığını iPhone'undaki Apple işlem kaydından kontrol eder. İadeler Apple tarafından reportaproblem.apple.com üzerinden yapılır.",
          "Where available in the app, CutSense Pro is a one-time in-app purchase sold through Apple's App Store. Apple processes the payment. We do not receive your card details, name, email, or Apple ID. The app checks whether Pro is unlocked from Apple's transaction record on your iPhone. Refunds are handled by Apple at reportaproblem.apple.com.",
        ),
      ],
    },
    {
      title: t("Saklama ve silme", "Retention and deletion"),
      body: [
        t(
          "Geçici video kopyaları iş bitince ve bir sonraki açılışta silinir. Cihazdaki ayarlar uygulamayı silene kadar kalır. Geçmiş (1.1 ve sonrası) en fazla 200 kayıt tutar; tek tek ya da Ayarlar > Geçmişi temizle ile hepsini silebilirsin. E-postalar talebin çözülene kadar saklanır. Google reklam verilerini kendi saklama politikasına göre tutar: policies.google.com/technologies/retention.",
          "Temporary video copies are deleted when the job ends and at the next launch. On-device settings remain until you delete the app. History (version 1.1 and later) keeps at most 200 entries; you can delete them one by one or all at once in Settings > Clear history. Emails are kept until your request is resolved. Google keeps advertising data according to its own retention policy: policies.google.com/technologies/retention.",
        ),
      ],
    },
    {
      title: t("Hakların", "Your rights"),
      body: [
        t(
          "Bulunduğun yere bağlı olarak verilerine erişme, düzeltme, silme, işlemeyi kısıtlama veya itiraz etme, taşınabilirlik ve rızanı geri çekme hakların olabilir; ayrıca yerel veri koruma otoritesine şikâyet edebilirsin. Talepler için bize yaz; 30 gün içinde yanıt veririz. Bölgeye özel ayrıntılar yukarıdaki GDPR, KVKK ve ABD bölümlerinde. Google'ın tuttuğu reklam verileri için Google'ın araçlarını kullanman gerekir, çünkü bu verilere biz erişemeyiz.",
          "Depending on where you live, you may have the right to access, correct, delete, restrict or object to processing of, and port your data, and to withdraw consent; you can also complain to your local data protection authority. Email us with any request and we will reply within 30 days. Region-specific details are in the GDPR, KVKK, and US sections above. For advertising data held by Google, use Google's tools, because we cannot access that data.",
        ),
      ],
    },
    {
      title: t("Uluslararası aktarımlar ve güvenlik", "International transfers and security"),
      body: [
        t(
          "Google verileri kendi ülkenin dışında, ABD dahil, işleyebilir ve bu aktarımlar için Standart Sözleşme Maddeleri gibi yasal mekanizmalar kullanır. Videoların cihazından çıkmadığı için en büyük koruma budur; iPhone'unun kendi güvenliği de geçerlidir.",
          "Google may process data outside your country, including in the United States, and uses legal mechanisms such as Standard Contractual Clauses for those transfers. Your videos never leave your device, which is the strongest protection we can offer; your iPhone's own security also applies.",
        ),
      ],
    },
    {
      title: t("Çocuklar", "Children"),
      body: [
        t(
          "CutSense 13 yaş altındaki çocuklara (ülkende dijital rıza yaşı daha yüksekse o yaşın altındakilere) yönelik değildir. Reklam istekleri çocuklara yönelik olarak işaretlenmez ve uygulama çocukların kendi başına kullanması için tasarlanmamıştır. Bilerek çocuklardan kişisel veri toplamayız.",
          "CutSense is not directed to children under 13 (or the higher digital-consent age in your country). Ad requests are not tagged as child-directed, and the app is not designed for children to use on their own. We do not knowingly collect personal data from children.",
        ),
        t(
          "Ebeveyn veya vasiysen ve çocuğunun bize veri gönderdiğini düşünüyorsan bize yaz; doğruladıktan sonra sileriz. Cihazdaki ayarlar ve Geçmiş, uygulamayı silerek kaldırılır; Google reklam verileri için Google'ın araçlarını kullan.",
          "If you are a parent or guardian and believe your child has sent us personal data, email us and we will delete it after verification. On-device settings and History are removed by deleting the app; for Google's advertising data, use Google's tools.",
        ),
      ],
    },
    {
      title: t("Web sitesi", "Website"),
      body: [
        t(
          "Bu web sitesi hesap, çerez, analiz veya reklam kullanmaz. Seçtiğin dil tarayıcının localStorage alanında saklanır ve bize gönderilmez. Site Cloudflare'de barındırılır; Cloudflare, siteyi sunmak ve korumak için IP adresi ve tarayıcı bilgisi gibi standart istek kayıtlarını işler.",
          "This website uses no account, cookies, analytics, or ads. Your language choice is stored in your browser's localStorage and is not sent to us. The site is hosted on Cloudflare, which processes standard request logs such as IP address and browser information to serve and protect the site.",
        ),
      ],
    },
    {
      title: t("Değişiklikler", "Changes"),
      body: [
        t(
          "Bu politikayı güncelleyebiliriz. Güncel sürüm her zaman bu sayfadadır ve yürürlük tarihi yukarıda yazar.",
          "We may update this policy. The current version is always on this page, with the effective date above.",
        ),
      ],
    },
    {
      title: t("İletişim", "Contact"),
      body: [
        t(
          `Veri sorumlusu: ${seller}, Türkiye. Gizlilik soruları ve talepleri için ${contact} adresine yaz.`,
          `Data controller: ${seller}, Türkiye. For privacy questions and requests, email ${contact}.`,
        ),
      ],
    },
  ];

  return (
    <main>
      <SiteNav />
      <article className="legal-shell">
        <p className="eyebrow">CutSense</p>
        <h1>{t("Gizlilik Politikası", "Privacy Policy")}</h1>
        <p className="legal-intro">
          {t(
            "Bu politika CutSense iPhone uygulamasının ve bu web sitesinin verileri nasıl ele aldığını açıklar.",
            "This policy explains how the CutSense iPhone app and this website handle data.",
          )}
        </p>
        <div className="legal-sections">
          {sections.map((section) => (
            <section key={section.title}>
              <h2>{section.title}</h2>
              {section.body.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
            </section>
          ))}
        </div>
      </article>
      <SiteFooter />
    </main>
  );
}
