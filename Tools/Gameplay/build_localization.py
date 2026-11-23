"""Build DemonShop localization table CSV and Studio sync script."""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = ROOT / "GameLocalizationTables" / "GameLocalizationTable.csv"
LUAU_PATH = ROOT / "Tools" / "Gameplay" / "sync-localization-table.luau"

LANGUAGES = [
    "ar", "de", "es", "fr", "id", "it", "ja", "ko",
    "pl", "pt", "ru", "th", "tr", "vi", "zh-hans", "zh-hant"
]

# (Key, Source, Context, Example, {lang: translation})
ENTRIES = [
    # --- 1. Parameterized Texts (8) ---
    (
        "Processing.TakePotion", "TAKE THE POTION TO THE SUMMONING SIGIL  (+{1} COINS)", "", "",
        {
            "zh-hans": "将药水带往召唤法阵  (+{1} 金币)", "zh-hant": "將藥水帶往召喚法陣  (+{1} 金幣)",
            "zh-cn": "将药水带往召唤法阵  (+{1} 金币)", "zh-tw": "將藥水帶往召喚法陣  (+{1} 金幣)",
            "ja": "ポーションを召喚陣に運ぶ (+{1} コイン)", "ko": "포션을 소환진으로 가져가세요 (+{1} 코인)",
            "es": "LLEVA LA POCIÓN AL CÍRCULO DE INVOCACIÓN (+{1} MONEDAS)",
            "fr": "APPORTEZ LA POTION AU CERCLE D'INVOCATION (+{1} PIÈCES)",
            "de": "BRINGE DEN TRANK ZUM BESCHWÖRUNGSKREIS (+{1} MÜNZEN)",
            "it": "PORTA LA POZIONE AL CIRCOLO DI EVOCAZIONE (+{1} MONETE)",
            "pt": "LEVE A POÇÃO PARA O CÍRCULO DE INVOCAÇÃO (+{1} MOEDAS)",
            "ru": "ОТНЕСИТЕ ЗЕЛЬЕ К КРУГУ ПРИЗЫВА (+{1} МОНЕТ)",
            "pl": "ZANIEŚ MIKSTURĘ DO KRĘGU PRZYWOŁANIA (+{1} MONET)",
            "tr": "İKSİRİ ÇAĞIRMA ÇEMBERİNE GÖTÜR (+{1} JETON)",
            "vi": "MANG THUỐC ĐẾN VÒNG TRÒN TRIỆU HỒI (+{1} XU)",
            "th": "นำยาพิษไปที่วงเวทอัญเชิญ (+{1} เหรียญ)",
            "id": "BAWA RAMUAN KE LINGKARAN PEMANGGILAN (+{1} KOIN)",
            "ar": "احمل الجرعة إلى دائرة الاستدعاء (+{1} عملة)"
        }
    ),
    (
        "Processing.StunNpc", "STUN A WHITE NPC WITH {1} CLUB HITS", "", "",
        {
            "zh-hans": "用木棒击打白色NPC {1} 次以将其击晕", "zh-hant": "用木棒擊打白色NPC {1} 次以將其擊暈",
            "zh-cn": "用木棒击打白色NPC {1} 次以将其击晕", "zh-tw": "用木棒擊打白色NPC {1} 次以將其擊暈",
            "ja": "棍棒で白いNPCを{1}回攻撃して気絶させる", "ko": "몽둥이로 흰색 NPC를 {1}번 때려 기절시키세요",
            "es": "ATURDE A UN NPC BLANCO CON {1} GOLPES DE GARROTE",
            "fr": "ASSOMMEZ UN PNJ BLANC AVEC {1} COUPS DE MASSUE",
            "de": "BETÄUBE EINEN WEISSEN NPC MIT {1} KEULENSCHLÄGEN",
            "it": "STORDISCI UN PNG BIANCO CON {1} COLPI DI CLAVA",
            "pt": "ATORDIA UM NPC BRANCO COM {1} GOLPES DE CLAVA",
            "ru": "ОГЛУШИТЕ БЕЛОГО NPC {1} УДАРАМИ ДУБИНКИ",
            "pl": "OGŁUSZ BIAŁEGO NPC {1} UDERZENIAMI PAŁKĄ",
            "tr": "BEYAZ NPC'Yİ {1} SOPA DARBESİYLE BAYILT",
            "vi": "LÀM CHOÁNG NPC TRẮNG VỚI {1} ĐÒN ĐÁNH BẰNG GẬY",
            "th": "ทำให้ NPC สีขาวสตันด้วยการตีไม้กระบอง {1} ครั้ง",
            "id": "LUMPUSKAN NPC PUTIH DENGAN {1} PUKULAN PENTUNGAN",
            "ar": "اصعق شخصية غير قابلة للعب بيضاء بـ {1} ضربات هراوة"
        }
    ),
    (
        "Processing.OfferPotion", "OFFER POTION  (+{1} COINS)", "", "",
        {
            "zh-hans": "提交药水  (+{1} 金币)", "zh-hant": "提交藥水  (+{1} 金幣)",
            "zh-cn": "提交药水  (+{1} 金币)", "zh-tw": "提交藥水  (+{1} 金幣)",
            "ja": "ポーションを捧げる (+{1} コイン)", "ko": "포션 바치기 (+{1} 코인)",
            "es": "OFRECER POCIÓN (+{1} MONEDAS)", "fr": "OFFRIR LA POTION (+{1} PIÈCES)",
            "de": "TRANK OPFERN (+{1} MÜNZEN)", "it": "OFFRI LA POZIONE (+{1} MONETE)",
            "pt": "OFERECER POÇÃO (+{1} MOEDAS)", "ru": "ПОЖЕРТВОВАТЬ ЗЕЛЬЕ (+{1} МОНЕТ)",
            "pl": "OFIARUJ MIKSTURĘ (+{1} MONET)", "tr": "İKSİR SUN (+{1} JETON)",
            "vi": "DÂNG THUỐC (+{1} XU)", "th": "ถวายยาพิษ (+{1} เหรียญ)",
            "id": "PERSEMBAHKAN RAMUAN (+{1} KOIN)", "ar": "تقديم الجرعة (+{1} عملة)"
        }
    ),
    (
        "Processing.Coins", "COINS  {1}", "", "",
        {
            "zh-hans": "金币  {1}", "zh-hant": "金幣  {1}",
            "zh-cn": "金币  {1}", "zh-tw": "金幣  {1}",
            "ja": "コイン {1}", "ko": "코인 {1}", "es": "MONEDAS {1}", "fr": "PIÈCES {1}",
            "de": "MÜNZEN {1}", "it": "MONETE {1}", "pt": "MOEDAS {1}", "ru": "МОНЕТЫ {1}",
            "pl": "MONETY {1}", "tr": "JETON {1}", "vi": "XU {1}", "th": "เหรียญ {1}",
            "id": "KOIN {1}", "ar": "عملات {1}"
        }
    ),
    (
        "Processing.Stock", "POOL {1}/{2}  |  POTIONS {3}/{4}", "", "",
        {
            "zh-hans": "存放池 {1}/{2}  |  药水 {3}/{4}", "zh-hant": "存放池 {1}/{2}  |  藥水 {3}/{4}",
            "zh-cn": "存放池 {1}/{2}  |  药水 {3}/{4}", "zh-tw": "存放池 {1}/{2}  |  藥水 {3}/{4}",
            "ja": "プール {1}/{2} | ポーション {3}/{4}", "ko": "보관소 {1}/{2} | 포션 {3}/{4}",
            "es": "POZO {1}/{2} | POCIONES {3}/{4}", "fr": "BASSIN {1}/{2} | POTIONS {3}/{4}",
            "de": "BECKEN {1}/{2} | TRÄNKE {3}/{4}", "it": "VASCA {1}/{2} | POZIONI {3}/{4}",
            "pt": "POÇO {1}/{2} | POÇÕES {3}/{4}", "ru": "ПУЛ {1}/{2} | ЗЕЛЬЯ {3}/{4}",
            "pl": "ZBIORNIK {1}/{2} | MIKSTURY {3}/{4}", "tr": "HAVUZ {1}/{2} | İKSİRLER {3}/{4}",
            "vi": "HỒ CHỨA {1}/{2} | THUỐC {3}/{4}", "th": "บ่อเก็บ {1}/{2} | ยา {3}/{4}",
            "id": "KOLAM {1}/{2} | RAMUAN {3}/{4}", "ar": "المستودع {1}/{2} | الجرعات {3}/{4}"
        }
    ),
    (
        "Processing.AltarCountdown", "ALTAR {1}s  |  POTIONS {2}/{3}", "", "",
        {
            "zh-hans": "祭坛 {1}秒  |  药水 {2}/{3}", "zh-hant": "祭壇 {1}秒  |  藥水 {2}/{3}",
            "zh-cn": "祭坛 {1}秒  |  药水 {2}/{3}", "zh-tw": "祭壇 {1}秒  |  藥水 {2}/{3}",
            "ja": "祭壇 {1}秒 | ポーション {2}/{3}", "ko": "제단 {1}초 | 포션 {2}/{3}",
            "es": "ALTAR {1}s | POCIONES {2}/{3}", "fr": "AUTEL {1}s | POTIONS {2}/{3}",
            "de": "ALTAR {1}s | TRÄNKE {2}/{3}", "it": "ALTARE {1}s | POZIONI {2}/{3}",
            "pt": "ALTAR {1}s | POÇÕES {2}/{3}", "ru": "АЛТАРЬ {1}с | ЗЕЛЬЯ {2}/{3}",
            "pl": "OŁTARZ {1}s | MIKSTURY {2}/{3}", "tr": "SUNAK {1}sn | İKSİRLER {2}/{3}",
            "vi": "BÀN THỜ {1}giây | THUỐC {2}/{3}", "th": "แท่นบูชา {1}วินาที | ยา {2}/{3}",
            "id": "ALTAR {1}d | RAMUAN {2}/{3}", "ar": "المذبح {1}ث | الجرعات {2}/{3}"
        }
    ),
    (
        "Processing.HitCount", "HIT {1} / {2}", "", "",
        {
            "zh-hans": "击打 {1} / {2}", "zh-hant": "擊打 {1} / {2}",
            "zh-cn": "击打 {1} / {2}", "zh-tw": "擊打 {1} / {2}",
            "ja": "攻撃 {1} / {2}", "ko": "타격 {1} / {2}", "es": "GOLPES {1} / {2}",
            "fr": "COUPS {1} / {2}", "de": "TREFFER {1} / {2}", "it": "COLPI {1} / {2}",
            "pt": "GOLPES {1} / {2}", "ru": "УДАР {1} / {2}", "pl": "UDERZENIA {1} / {2}",
            "tr": "DARBE {1} / {2}", "vi": "ĐÁNH {1} / {2}", "th": "การโจมตี {1} / {2}",
            "id": "PUKULAN {1} / {2}", "ar": "ضربات {1} / {2}"
        }
    ),
    (
        "Processing.CoinsAwarded", "+{1} COINS", "", "",
        {
            "zh-hans": "+{1} 金币", "zh-hant": "+{1} 金幣",
            "zh-cn": "+{1} 金币", "zh-tw": "+{1} 金幣",
            "ja": "+{1} コイン", "ko": "+{1} 코인", "es": "+{1} MONEDAS", "fr": "+{1} PIÈCES",
            "de": "+{1} MÜNZEN", "it": "+{1} MONETE", "pt": "+{1} MOEDAS", "ru": "+{1} МОНЕТ",
            "pl": "+{1} MONET", "tr": "+{1} JETON", "vi": "+{1} XU", "th": "+{1} เหรียญ",
            "id": "+{1} KOIN", "ar": "+{1} عملة"
        }
    ),

    # --- 2. Prompts (9) ---
    (
        "", "PICK UP", "", "",
        {
            "zh-hans": "拾取", "zh-hant": "拾取", "zh-cn": "拾取", "zh-tw": "拾取",
            "ja": "拾う", "ko": "줍기", "es": "RECOGER", "fr": "RAMASSER",
            "de": "AUFHEBEN", "it": "RACCOGLI", "pt": "PEGAR", "ru": "ПОДОБРАТЬ",
            "pl": "PODNIEŚ", "tr": "TOPLA", "vi": "NHẶT LÊN", "th": "เก็บ",
            "id": "AMBIL", "ar": "التقاط"
        }
    ),
    (
        "", "HOLDING POOL", "", "",
        {
            "zh-hans": "存放池", "zh-hant": "存放池", "zh-cn": "存放池", "zh-tw": "存放池",
            "ja": "保管プール", "ko": "보관소", "es": "POZO DE CONTENCIÓN", "fr": "BASSIN DE RÉTENTION",
            "de": "AUFFANGBECKEN", "it": "VASCA DI CONTENIMENTO", "pt": "POÇO DE CONTENÇÃO", "ru": "ПУЛ ХРАНЕНИЯ",
            "pl": "ZBIORNIK PRZECHOWYWANIA", "tr": "TUTMA HAVUZU", "vi": "HỒ CHỨA", "th": "บ่อกักเก็บ",
            "id": "KOLAM PENAMPUNGAN", "ar": "حوض الاحتجاز"
        }
    ),
    (
        "", "RUNE TABLE", "", "",
        {
            "zh-hans": "符文工作台", "zh-hant": "符文工作台", "zh-cn": "符文工作台", "zh-tw": "符文工作台",
            "ja": "ルーン作業台", "ko": "룬 작업대", "es": "MESA DE RUNAS", "fr": "TABLE DE RUNES",
            "de": "RUNENTISCH", "it": "TAVOLO DELLE RUNE", "pt": "MESA DE RUNAS", "ru": "РУНИЧЕСКИЙ СТОЛ",
            "pl": "STÓŁ RUNICZNY", "tr": "RÜN MASASI", "vi": "BÀN PHÙ VĂN", "th": "โต๊ะรูน",
            "id": "MEJA RUNE", "ar": "طاولة الرون"
        }
    ),
    (
        "", "CONVERSION ALTAR", "", "",
        {
            "zh-hans": "转化祭坛", "zh-hant": "轉化祭壇", "zh-cn": "转化祭坛", "zh-tw": "轉化祭壇",
            "ja": "変換の祭壇", "ko": "변환 제단", "es": "ALTAR DE CONVERSIÓN", "fr": "AUTEL DE CONVERSION",
            "de": "UMWANDLUNGSALTAR", "it": "ALTARE DI CONVERSIONE", "pt": "ALTAR DE CONVERSÃO", "ru": "АЛТАРЬ ПРЕОБРАЗОВАНИЯ",
            "pl": "OŁTARZ KONWERSJI", "tr": "DÖNÜŞÜM SUNAĞI", "vi": "BÀN THỜ CHUYỂN HÓA", "th": "แท่นบูชาแปลงสภาพ",
            "id": "ALTAR KONVERSI", "ar": "مذبح التحويل"
        }
    ),
    (
        "", "POTION SHELF", "", "",
        {
            "zh-hans": "药水架", "zh-hant": "藥水架", "zh-cn": "药水架", "zh-tw": "藥水架",
            "ja": "ポーション棚", "ko": "포션 선반", "es": "ESTANTE DE POCIONES", "fr": "ÉTAGÈRE À POTIONS",
            "de": "TRANKREGAL", "it": "SCAFFALE DELLE POZIONI", "pt": "PRATELEIRA DE POÇÕES", "ru": "ПОЛКА ДЛЯ ЗЕЛИЙ",
            "pl": "PÓŁKA NA MIKSTURY", "tr": "İKSİR RAFI", "vi": "GIÁ THUỐC", "th": "ชั้นวางยา",
            "id": "RAK RAMUAN", "ar": "رف الجرعات"
        }
    ),
    (
        "", "SUMMONING SIGIL", "", "",
        {
            "zh-hans": "召唤法阵", "zh-hant": "召喚法陣", "zh-cn": "召唤法阵", "zh-tw": "召喚法陣",
            "ja": "召喚陣", "ko": "소환진", "es": "CÍRCULO DE INVOCACIÓN", "fr": "CERCLE D'INVOCATION",
            "de": "BESCHWÖRUNGSSIEGEL", "it": "SIGILLO DI EVOCAZIONE", "pt": "SÍMBOLO DE INVOCAÇÃO", "ru": "СИГИЛ ПРИЗЫВА",
            "pl": "SYMBOL PRZYWOŁANIA", "tr": "ÇAĞIRMA MÜHRÜ", "vi": "VÒNG PHÙ HIỆU TRIỆU HỒI", "th": "สัญลักษณ์อัญเชิญ",
            "id": "SEGEL PEMANGGILAN", "ar": "ختم الاستدعاء"
        }
    ),
    (
        "", "BODY", "", "",
        {
            "zh-hans": "躯体", "zh-hant": "軀體", "zh-cn": "躯体", "zh-tw": "軀體",
            "ja": "体", "ko": "신체", "es": "CUERPO", "fr": "CORPS",
            "de": "KÖRPER", "it": "CORPO", "pt": "CORPO", "ru": "ТЕЛО",
            "pl": "CIAŁO", "tr": "GÖVDE", "vi": "THÂN THỂ", "th": "ร่าง",
            "id": "TUBUH", "ar": "جسد"
        }
    ),
    (
        "", "POTION", "", "",
        {
            "zh-hans": "灵魂药水", "zh-hant": "靈魂藥水", "zh-cn": "灵魂药水", "zh-tw": "靈魂藥水",
            "ja": "ポーション", "ko": "포션", "es": "POCIÓN", "fr": "POTION",
            "de": "TRANK", "it": "POZIONE", "pt": "POÇÃO", "ru": "ЗЕЛЬЕ",
            "pl": "MIKSTURA", "tr": "İKSİR", "vi": "THUỐC", "th": "ยาพิษ",
            "id": "RAMUAN", "ar": "جرعة"
        }
    ),
    (
        "", "OFFER POTION", "", "",
        {
            "zh-hans": "献祭药水", "zh-hant": "獻祭藥水", "zh-cn": "献祭药水", "zh-tw": "獻祭藥水",
            "ja": "ポーションを捧げる", "ko": "포션 바치기", "es": "OFRECER POCIÓN", "fr": "OFFRIR LA POTION",
            "de": "TRANK OPFERN", "it": "OFFRI LA POZIONE", "pt": "OFERECER POÇÃO", "ru": "ПОЖЕРТВОВАТЬ ЗЕЛЬЕ",
            "pl": "OFIARUJ MIKSTURĘ", "tr": "İKSİR SUN", "vi": "DÂNG THUỐC", "th": "ถวายยา",
            "id": "PERSEMBAHKAN RAMUAN", "ar": "تقديم الجرعة"
        }
    ),

    # --- 3. Guidance (6 without args) ---
    (
        "", "TAKE THE RUNE BODY TO THE CONVERSION ALTAR", "", "",
        {
            "zh-hans": "将符文躯体带往转化祭坛", "zh-hant": "將符文軀體帶往轉化祭壇",
            "zh-cn": "将符文躯体带往转化祭坛", "zh-tw": "將符文軀體帶往轉化祭壇",
            "ja": "ルーンの体を変換の祭壇へ運ぶ", "ko": "룬 신체를 변환 제단으로 가져가세요",
            "es": "LLEVA EL CUERPO RÚNICO AL ALTAR DE CONVERSIÓN",
            "fr": "APPORTEZ LE CORPS RUNIQUE À L'AUTEL DE CONVERSION",
            "de": "BRINGE DEN RUNENKÖRPER ZUM UMWANDLUNGSALTAR",
            "it": "PORTA IL CORPO RUNICO ALL'ALTARE DI CONVERSIONE",
            "pt": "LEVE O CORPO RÚNICO AO ALTAR DE CONVERSÃO",
            "ru": "ОТНЕСИТЕ РУНИЧЕСКОЕ ТЕЛО К АЛТАРЮ ПРЕОБРАЗОВАНИЯ",
            "pl": "ZANIEŚ CIAŁO RUNICZNE DO OŁTARZA KONWERSJI",
            "tr": "RÜNLÜ GÖVDESİNİ DÖNÜŞÜM SUNAĞINA GÖTÜR",
            "vi": "MANG THÂN THỂ PHÙ VĂN ĐẾN BÀN THỜ CHUYỂN HÓA",
            "th": "นำร่างรูนไปที่แท่นบูชาแปลงสภาพ",
            "id": "BAWA TUBUH RUNE KE ALTAR KONVERSI",
            "ar": "احمل جسد الرون إلى مذبح التحويل"
        }
    ),
    (
        "", "TAKE THE BODY DOWNSTAIRS TO THE RUNE TABLE OR HOLDING POOL", "", "",
        {
            "zh-hans": "将躯体带往楼下的符文工作台或存放池", "zh-hant": "將軀體帶往樓下的符文工作台或存放池",
            "zh-cn": "将躯体带往楼下的符文工作台或存放池", "zh-tw": "將軀體帶往樓下的符文工作台或存放池",
            "ja": "体を階下のルーン作業台または保管プールへ運ぶ", "ko": "신체를 아래층 룬 작업대나 보관소로 가져가세요",
            "es": "LLEVA EL CUERPO ABAJO A LA MESA DE RUNAS O AL POZO",
            "fr": "APPORTEZ LE CORPS EN BAS À LA TABLE DE RUNES OU AU BASSIN",
            "de": "BRINGE DEN KÖRPER NACH UNTEN ZUM RUNENTISCH ODER BECKEN",
            "it": "PORTA IL CORPO DI SOTTO AL TAVOLO DELLE RUNE O ALLA VASCA",
            "pt": "LEVE O CORPO PARA BAIXO ATÉ A MESA DE RUNAS OU POÇO",
            "ru": "СПУСТИТЕ ТЕЛО ВНИЗ К РУНИЧЕСКОМУ СТОЛУ ИЛИ ПУЛУ",
            "pl": "ZANIEŚ CIAŁO NA DÓŁ DO STOŁU RUNICZNEGO LUB ZBIORNIKA",
            "tr": "GÖVDEYİ AŞAĞIYA, RÜN MASASINA VEYA HAVUZA GÖTÜR",
            "vi": "MANG THÂN THỂ XUỐNG DƯỚI BÀN PHÙ VĂN HOẶC HỒ CHỨA",
            "th": "นำร่างลงไปข้างล่างที่โต๊ะรูนหรือบ่อกักเก็บ",
            "id": "BAWA TUBUH KE LANTAI BAWAH KE MEJA RUNE ATAU KOLAM",
            "ar": "انزل بالجسد إلى طاولة الرون أو حوض الاحتجاز"
        }
    ),
    (
        "", "A POTION IS READY - COLLECT IT FROM THE SHELF", "", "",
        {
            "zh-hans": "药水已炼制完成 - 请从药水架领取", "zh-hant": "藥水已煉製完成 - 請從藥水架領取",
            "zh-cn": "药水已炼制完成 - 请从药水架领取", "zh-tw": "藥水已煉製完成 - 請從藥水架領取",
            "ja": "ポーションが完成しました - 棚から回収してください",
            "ko": "포션이 준비되었습니다 - 선반에서 수령하세요",
            "es": "UNA POCIÓN ESTÁ LISTA - RECOGE DEL ESTANTE",
            "fr": "UNE POTION EST PRÊTE - RÉCUPÉREZ-LA SUR L'ÉTAGÈRE",
            "de": "EIN TRANK IST BEREIT - NIMM IHN AUS DEM REGAL",
            "it": "UNA POZIONE È PRONTA - RITIRALA DALLO SCAFFALE",
            "pt": "UMA POÇÃO ESTÁ PRONTA - RECOLHA DA PRATELEIRA",
            "ru": "ЗЕЛЬЕ ГОТОВО - ЗАБЕРИТЕ ЕГО С ПОЛКИ",
            "pl": "MIKSTURA JEST GOTOWA - ODBIERZ JĄ Z PÓŁKI",
            "tr": "BİR İKSİR HAZIR - RAFTAN AL",
            "vi": "THUỐC ĐÃ SẴN SÀNG - HÃY LẤY TỪ GIÁ",
            "th": "ยามีความพร้อมแล้ว - เก็บจากชั้นวาง",
            "id": "RAMUAN SIAP - AMBIL DARI RAK",
            "ar": "الجرعة جاهزة - خذها من الرف"
        }
    ),
    (
        "", "THE ALTAR IS WORKING - CHECK THE COUNTDOWN", "", "",
        {
            "zh-hans": "祭坛转化中 - 请留意倒计时", "zh-hant": "祭壇轉化中 - 請留意倒計時",
            "zh-cn": "祭坛转化中 - 请留意倒计时", "zh-tw": "祭壇轉化中 - 請留意倒計時",
            "ja": "祭壇が稼働中 - カウントダウンを確認してください",
            "ko": "제단이 작동 중입니다 - 카운트다운을 확인하세요",
            "es": "EL ALTAR ESTÁ FUNCIONANDO - MIRA LA CUENTA REGRESIVA",
            "fr": "L'AUTEL FONCTIONNE - VÉRIFIEZ LE COMPTE À REBOURS",
            "de": "DER ALTAR ARBEITET - PRÜFE DEN COUNTDOWN",
            "it": "L'ALTARE È IN FUNZIONE - CONTROLLA IL CONTO ALLA ROVESCIA",
            "pt": "O ALTAR ESTÁ FUNCIONANDO - VEJA A CONTAGEM REGRESSIVA",
            "ru": "АЛТАРЬ РАБОТАЕТ - СЛЕДИТЕ ЗА ТАЙМЕРОМ",
            "pl": "OŁTARZ PRACUJE - SPRAWDŹ ODLICZANIE",
            "tr": "SUNAK ÇALIŞIYOR - GERİ SAYIMI KONTROL ET",
            "vi": "BÀN THỜ ĐANG HOẠT ĐỘNG - XEM ĐẾM NGƯỢC",
            "th": "แท่นบูชากำลังทำงาน - ตรวจสอบเวลานับถอยหลัง",
            "id": "ALTAR SEDANG BEKERJA - LIHAT HITUNG MUNDUR",
            "ar": "المذبح يعمل - تحقق من العد التنازلي"
        }
    ),
    (
        "", "RETURN TO THE RUNE TABLE TO CONTINUE OR COLLECT THE BODY", "", "",
        {
            "zh-hans": "返回符文工作台以继续绘制或取走躯体", "zh-hant": "返回符文工作台以繼續繪製或取走軀體",
            "zh-cn": "返回符文工作台以继续绘制或取走躯体", "zh-tw": "返回符文工作台以繼續繪製或取走軀體",
            "ja": "ルーン作業台に戻って描画を続けるか体を回収してください",
            "ko": "룬 작업대로 돌아가 그리기를 계속하거나 신체를 회수하세요",
            "es": "REGRESA A LA MESA DE RUNAS PARA CONTINUAR O RECOGER EL CUERPO",
            "fr": "RETOURNEZ À LA TABLE DE RUNES POUR CONTINUER OU RAMASSER LE CORPS",
            "de": "KEHRE ZUM RUNENTISCH ZURÜCK, UM WEITERZUMALEN ODER DEN KÖRPER ZU HOLEN",
            "it": "TORNA AL TAVOLO DELLE RUNE PER CONTINUARE O PRENDERE IL CORPO",
            "pt": "RETORNE À MESA DE RUNAS PARA CONTINUAR OU PEGAR O CORPO",
            "ru": "ВЕРНИТЕСЬ К РУНИЧЕСКОМУ СТОЛУ ДЛЯ ПРОДОЛЖЕНИЯ ИЛИ ЗАБОРА ТЕЛА",
            "pl": "WRÓĆ DO STOŁU RUNICZNEGO, ABY KONTYNUOWAĆ LUB ODEBRAĆ CIAŁO",
            "tr": "DEVAM ETMEK VEYA GÖVDEYİ ALMAK İÇİN RÜN MASASINA DÖN",
            "vi": "QUAY LẠI BÀN PHÙ VĂN ĐỂ TIẾP TỤC HOẶC LẤY THÂN THỂ",
            "th": "กลับไปที่โต๊ะรูนเพื่อวาดต่อหรือเก็บร่าง",
            "id": "KEMBALI KE MEJA RUNE UNTUK MELANJUTKAN ATAU MENGAMBIL TUBUH",
            "ar": "عد إلى طاولة الرون للمتابعة أو استلام الجسد"
        }
    ),
    (
        "", "THE RUNE TABLE CAN FETCH A BODY FROM THE SHARED POOL", "", "",
        {
            "zh-hans": "可直接在工作台取出共享池中的躯体", "zh-hant": "可直接在工作台取出共享池中的軀體",
            "zh-cn": "可直接在工作台取出共享池中的躯体", "zh-tw": "可直接在工作台取出共享池中的軀體",
            "ja": "共有プールからルーン作業台に体を呼び出せます",
            "ko": "룬 작업대에서 공유 보관소의 신체를 꺼낼 수 있습니다",
            "es": "LA MESA DE RUNAS PUEDE TOMAR UN CUERPO DEL POZO COMPARTIDO",
            "fr": "LA TABLE DE RUNES PEUT RÉCUPÉRER UN CORPS DANS LE BASSIN PARTAGÉ",
            "de": "DER RUNENTISCH KANN EINEN KÖRPER AUS DEM GEMEINSAMEN BECKEN HOLEN",
            "it": "IL TAVOLO DELLE RUNE PUÒ PRELEVARE UN CORPO DALLA VASCA CONDIVISA",
            "pt": "A MESA DE RUNAS PODE PEGAR UM CORPO DO POÇO COMPARTILHADO",
            "ru": "РУНИЧЕСКИЙ СТОЛ МОЖЕТ ВЗЯТЬ ТЕЛО ИЗ ОБЩЕГО ПУЛА",
            "pl": "STÓŁ RUNICZNY MOŻE POBRAĆ CIAŁO ZE WSPÓLNEGO ZBIORNIKA",
            "tr": "RÜN MASASI ORTAK HAVUZDAN BİR GÖVDE ÇEKEBİLİR",
            "vi": "BÀN PHÙ VĂN CÓ THỂ LẤY THÂN THỂ TỪ HỒ DÙNG CHUNG",
            "th": "โต๊ะรูนสามารถดึงร่างจากบ่อส่วนกลางได้",
            "id": "MEJA RUNE DAPAT MENGAMBIL TUBUH DARI KOLAM BERSAMA",
            "ar": "يمكن لطاولة الرون جلب جسد من الحوض المشترك"
        }
    ),

    # --- 4. Interactions (22 without args) ---
    (
        "", "POOL ACCEPTS UNFINISHED BODIES ONLY", "", "",
        {
            "zh-hans": "存放池仅接收未完成的躯体", "zh-hant": "存放池僅接收未完成的軀體",
            "zh-cn": "存放池仅接收未完成的躯体", "zh-tw": "存放池僅接收未完成的軀體",
            "ja": "プールは未完成の体のみ受け入れます", "ko": "보관소에는 미완성된 신체만 넣을 수 있습니다",
            "es": "EL POZO SOLO ACEPTA CUERPOS INCOMPLETOS", "fr": "LE BASSIN N'ACCEPTE QUE LES CORPS INACHEVÉS",
            "de": "DAS BECKEN NIMMT NUR UNFERTIGE KÖRPER AN", "it": "LA VASCA ACCETTA SOLO CORPI INCOMPLETI",
            "pt": "O POÇO SÓ ACEITA CORPOS INCOMPLETOS", "ru": "В ПУЛ ПРИНИМАЮТСЯ ТОЛЬКО НЕЗАВЕРШЕННЫЕ ТЕЛА",
            "pl": "ZBIORNIK PRZYJMUJE TYLKO NIEDOKOŃCZONE CIAŁA", "tr": "HAVUZ YALNIZCA TAMAMLANMAMIŞ GÖVDELERİ KABUL EDER",
            "vi": "HỒ CHỈ CHẤP NHẬN THÂN THỂ CHƯA HOÀN THÀNH", "th": "บ่อกักเก็บรับเฉพาะร่างที่ยังไม่เสร็จเท่านั้น",
            "id": "KOLAM HANYA MENERIMA TUBUH YANG BELUM SELESAI", "ar": "يقبل الحوض الأجساد غير المكتملة فقط"
        }
    ),
    (
        "", "STORE UNFINISHED BODY", "", "",
        {
            "zh-hans": "存放未完成躯体", "zh-hant": "存放未完成軀體", "zh-cn": "存放未完成躯体", "zh-tw": "存放未完成軀體",
            "ja": "未完成の体を保管", "ko": "미완성 신체 보관", "es": "GUARDAR CUERPO INCOMPLETO",
            "fr": "STOCKER LE CORPS INACHEVÉ", "de": "UNFERTIGEN KÖRPER LAGERN", "it": "CONSERVA IL CORPO INCOMPLETO",
            "pt": "GUARDAR CORPO INCOMPLETO", "ru": "СОХРАНИТЬ НЕЗАВЕРШЕННОЕ ТЕЛО", "pl": "PRZECHOWAJ NIEDOKOŃCZONE CIAŁO",
            "tr": "TAMAMLANMAMIŞ GÖVDEYİ SAKLA", "vi": "LƯU TRỮ THÂN THỂ CHƯA HOÀN THÀNH", "th": "จัดเก็บร่างที่ยังไม่เสร็จ",
            "id": "SIMPAN TUBUH BELUM SELESAI", "ar": "تخزين جسد غير مكتمل"
        }
    ),
    (
        "", "TAKE FIRST SHARED BODY", "", "",
        {
            "zh-hans": "取出第一个共享躯体", "zh-hant": "取出第一個共享軀體", "zh-cn": "取出第一个共享躯体", "zh-tw": "取出第一個共享軀體",
            "ja": "最初の共有体を取り出す", "ko": "첫 번째 공유 신체 가져오기", "es": "TOMAR EL PRIMER CUERPO COMPARTIDO",
            "fr": "PRENDRE LE PREMIER CORPS PARTAGÉ", "de": "ERSTEN GEMEINSAMEN KÖRPER NEHMEN", "it": "PRENDI IL PRIMO CORPO CONDIVISO",
            "pt": "PEGAR O PRIMEIRO CORPO COMPARTILHADO", "ru": "ВЗЯТЬ ПЕРВОЕ ОБЩЕЕ ТЕЛО", "pl": "WEŹ PIERWSZE WSPÓLNE CIAŁO",
            "tr": "İLK ORTAK GÖVDEYİ AL", "vi": "LẤY THÂN THỂ DÙNG CHUNG ĐẦU TIÊN", "th": "หยิบร่างส่วนกลางร่างแรก",
            "id": "AMBIL TUBUH BERSAMA PERTAMA", "ar": "خذ أول جسد مشترك"
        }
    ),
    (
        "", "POOL EMPTY - BRING A BODY", "", "",
        {
            "zh-hans": "存放池为空 - 请先带来躯体", "zh-hant": "存放池為空 - 請先帶來軀體",
            "zh-cn": "存放池为空 - 请先带来躯体", "zh-tw": "存放池為空 - 請先帶來軀體",
            "ja": "プールが空です - 体を持ってきてください", "ko": "보관소가 비어 있습니다 - 신체를 가져오세요",
            "es": "POZO VACÍO - TRAE UN CUERPO", "fr": "BASSIN VIDE - APPORTEZ UN CORPS",
            "de": "BECKEN LEER - BRINGE EINEN KÖRPER", "it": "VASCA VUOTA - PORTA UN CORPO",
            "pt": "POÇO VAZIO - TRAGA UM CORPO", "ru": "ПУЛ ПУСТ - ПРИНЕСИТЕ ТЕЛО",
            "pl": "ZBIORNIK PUSTY - PRZYNIEŚ CIAŁO", "tr": "HAVUZ BOŞ - BİR GÖVDE GETİR",
            "vi": "HỒ RỖNG - HÃY MANG THÂN THỂ ĐẾN", "th": "บ่อว่างเปล่า - โปรดนำร่างมา",
            "id": "KOLAM KOSONG - BAWA TUBUH", "ar": "الحوض فارغ - احضر جسدا"
        }
    ),
    (
        "", "TABLE IN USE - ANOTHER PLAYER IS PAINTING", "", "",
        {
            "zh-hans": "工作台使用中 - 其他玩家正在绘制", "zh-hant": "工作台使用中 - 其他玩家正在繪製",
            "zh-cn": "工作台使用中 - 其他玩家正在绘制", "zh-tw": "工作台使用中 - 其他玩家正在繪製",
            "ja": "作業台は使用中 - 他のプレイヤーが描画しています",
            "ko": "작업대 사용 중 - 다른 플레이어가 그리는 중입니다",
            "es": "MESA EN USO - OTRO JUGADOR ESTÁ PINTANDO",
            "fr": "TABLE OCCUPÉE - UN AUTRE JOUEUR EST EN TRAIN DE PEINDRE",
            "de": "TISCH BESETZT - EIN ANDERER SPIELER MALT",
            "it": "TAVOLO OCCUPATO - UN ALTRO GIOCATORE STA DIPINGENDO",
            "pt": "MESA EM USO - OUTRO JOGADOR ESTÁ PINTANDO",
            "ru": "СТОЛ ЗАНЯТ - ДРУГОЙ ИГРОК РИСУЕТ",
            "pl": "STÓŁ ZAJĘTY - INNY GRACZ MALUJE",
            "tr": "MASA KULLANIMDA - BAŞKA BİR OYUNCU ÇİZİYOR",
            "vi": "BÀN ĐANG ĐƯỢC DÙNG - NGƯỜI CHƠI KHÁC ĐANG VẼ",
            "th": "โต๊ะกำลังใช้งาน - ผู้เล่นอื่นกำลังวาดอยู่",
            "id": "MEJA SEDANG DIGUNAKAN - PEMAIN LAIN SEDANG MELUKIS",
            "ar": "الطاولة مشغولة - لاعب آخر يقوم بالرسم"
        }
    ),
    (
        "", "TABLE OCCUPIED - PUT DOWN YOUR ITEM FIRST", "", "",
        {
            "zh-hans": "工作台已被占用 - 请先放下手中物品", "zh-hant": "工作台已被佔用 - 請先放下手中物品",
            "zh-cn": "工作台已被占用 - 请先放下手中物品", "zh-tw": "工作台已被佔用 - 請先放下手中物品",
            "ja": "作業台は埋まっています - 先にアイテムを置いてください",
            "ko": "작업대가 차 있습니다 - 먼저 들고 있는 물건을 내려놓으세요",
            "es": "MESA OCUPADA - DEJA TU OBJETO PRIMERO",
            "fr": "TABLE OCCUPÉE - DÉPOSEZ D'ABORD VOTRE OBJET",
            "de": "TISCH BESETZT - LEGE ZUERST DEINEN GEGENSTAND AB",
            "it": "TAVOLO OCCUPATO - POSA PRIMA IL TUO OGGETTO",
            "pt": "MESA OCUPADA - LARGUE SEU ITEM PRIMEIRO",
            "ru": "СТОЛ ЗАНЯТ - СНАЧАЛА ПОЛОЖИТЕ ПРЕДМЕТ",
            "pl": "STÓŁ ZAJĘTY - NAJPIERW ODŁÓŻ PRZEDMIOT",
            "tr": "MASA DOLU - ÖNCE EŞYANI BIRAK",
            "vi": "BÀN ĐÃ ĐẦY - HÃY ĐẶT VẬT PHẨM XUỐNG TRƯỚC",
            "th": "โต๊ะไม่ว่าง - วางไอเทมลงก่อน",
            "id": "MEJA PENUH - LETAKKAN BARANGMU DAHULU",
            "ar": "الطاولة ممتلئة - ضع العنصر أولا"
        }
    ),
    (
        "", "PLACE BODY ON RUNE TABLE", "", "",
        {
            "zh-hans": "将躯体放置在符文工作台", "zh-hant": "將軀體放置在符文工作台",
            "zh-cn": "将躯体放置在符文工作台", "zh-tw": "將軀體放置在符文工作台",
            "ja": "体をルーン作業台に置く", "ko": "룬 작업대에 신체 놓기",
            "es": "COLOCA EL CUERPO EN LA MESA DE RUNAS", "fr": "PLACER LE CORPS SUR LA TABLE DE RUNES",
            "de": "PLATZIERE DEN KÖRPER AUF DEM RUNENTISCH", "it": "POSIZIONA IL CORPO SUL TAVOLO DELLE RUNE",
            "pt": "COLOQUE O CORPO NA MESA DE RUNAS", "ru": "ПОЛОЖИТЕ ТЕЛО НА РУНИЧЕСКИЙ СТОЛ",
            "pl": "POŁÓŻ CIAŁO NA STOLE RUNICZNYM", "tr": "GÖVDEYİ RÜN MASASINA YERLEŞTİR",
            "vi": "ĐẶT THÂN THỂ LÊN BÀN PHÙ VĂN", "th": "วางร่างลงบนโต๊ะรูน",
            "id": "LETAKKAN TUBUH DI MEJA RUNE", "ar": "ضع الجسد على طاولة الرون"
        }
    ),
    (
        "", "TABLE NEEDS AN UNFINISHED BODY", "", "",
        {
            "zh-hans": "工作台需要放置未完成的躯体", "zh-hant": "工作台需要放置未完成的軀體",
            "zh-cn": "工作台需要放置未完成的躯体", "zh-tw": "工作台需要放置未完成的軀體",
            "ja": "作業台には未完成の体が必要です", "ko": "작업대에는 미완성 신체가 필요합니다",
            "es": "LA MESA NECESITA UN CUERPO INCOMPLETO", "fr": "LA TABLE A BESOIN D'UN CORPS INACHEVÉ",
            "de": "DER TISCH BRAUCHT EINEN UNFERTIGEN KÖRPER", "it": "IL TAVOLO RICHIEDE UN CORPO INCOMPLETO",
            "pt": "A MESA PRECISA DE UM CORPO INCOMPLETO", "ru": "ДЛЯ СТОЛА ТРЕБУЕТСЯ НЕЗАВЕРШЕННОЕ ТЕЛО",
            "pl": "STÓŁ WYMAGA NIEDOKOŃCZONEGO CIAŁA", "tr": "MASAYA TAMAMLANMAMIŞ BİR GÖVDE LAZIM",
            "vi": "BÀN CẦN THÂN THỂ CHƯA HOÀN THÀNH", "th": "โต๊ะต้องการร่างที่ยังไม่เสร็จ",
            "id": "MEJA MEMBUTUHKAN TUBUH BELUM SELESAI", "ar": "تحتاج الطاولة إلى جسد غير مكتمل"
        }
    ),
    (
        "", "COLLECT COMPLETED RUNE BODY", "", "",
        {
            "zh-hans": "领取已完成画符的躯体", "zh-hant": "領取已完成畫符的軀體",
            "zh-cn": "领取已完成画符的躯体", "zh-tw": "領取已完成畫符的軀體",
            "ja": "完成したルーンの体を回収", "ko": "완성된 룬 신체 회수",
            "es": "RECOGER CUERPO RÚNICO COMPLETADO", "fr": "RÉCUPÉRER LE CORPS RUNIQUE TERMINÉ",
            "de": "FERTIGEN RUNENKÖRPER ABHOLEN", "it": "RITIRA IL CORPO RUNICO COMPLETATO",
            "pt": "PEGAR CORPO RÚNICO CONCLUÍDO", "ru": "ЗАБРАТЬ ГОТОВОЕ РУНИЧЕСКОЕ ТЕЛО",
            "pl": "ODBIERZ DOKOŃCZONE CIAŁO RUNICZNE", "tr": "TAMAMLANMIŞ RÜNLÜ GÖVDESİNİ AL",
            "vi": "LẤY THÂN THỂ PHÙ VĂN HOÀN CHỈNH", "th": "เก็บร่างรูนที่เสร็จสมบูรณ์",
            "id": "AMBIL TUBUH RUNE YANG SELESAI", "ar": "استلم جسد الرون المكتمل"
        }
    ),
    (
        "", "CONTINUE PAINTING THE BODY", "", "",
        {
            "zh-hans": "继续绘制躯体符文", "zh-hant": "繼續繪製軀體符文",
            "zh-cn": "继续绘制躯体符文", "zh-tw": "繼續繪製軀體符文",
            "ja": "体の描画を続ける", "ko": "신체 그리기 계속하기",
            "es": "CONTINUAR PINTANDO EL CUERPO", "fr": "CONTINUER À PEINDRE LE CORPS",
            "de": "WEITER AM KÖRPER MALEN", "it": "CONTINUA A DIPINGERE IL CORPO",
            "pt": "CONTINUAR PINTANDO O CORPO", "ru": "ПРОДОЛЖИТЬ РИСОВАНИЕ НА ТЕЛЕ",
            "pl": "KONTYNUUJ MALOWANIE CIAŁA", "tr": "GÖVDEYİ ÇİZMEYE DEVAM ET",
            "vi": "TIẾP TỤC VẼ LÊN THÂN THỂ", "th": "วาดร่างต่อไป",
            "id": "LANJUTKAN MELUKIS TUBUH", "ar": "تابع الرسم على الجسد"
        }
    ),
    (
        "", "FETCH SHARED BODY AND PAINT", "", "",
        {
            "zh-hans": "从共享池取出躯体并绘制", "zh-hant": "從共享池取出軀體並繪製",
            "zh-cn": "从共享池取出躯体并绘制", "zh-tw": "從共享池取出軀體並繪製",
            "ja": "共有体を取得して描画", "ko": "공유 신체를 꺼내 그리기",
            "es": "OBTENER CUERPO COMPARTIDO Y PINTAR", "fr": "RÉCUPÉRER UN CORPS PARTAGÉ ET PEINDRE",
            "de": "GEMEINSAMEN KÖRPER HOLEN UND MALEN", "it": "PRELEVA IL CORPO CONDIVISO E DIPINGI",
            "pt": "PEGAR CORPO COMPARTILHADO E PINTAR", "ru": "ВЗЯТЬ ОБЩЕЕ ТЕЛО И РИСОВАТЬ",
            "pl": "POBIERZ WSPÓLNE CIAŁO I MALUJ", "tr": "ORTAK GÖVDEYİ AL VE ÇİZ",
            "vi": "LẤY THÂN THỂ DÙNG CHUNG VÀ VẼ", "th": "ดึงร่างส่วนกลางมาวาด",
            "id": "AMBIL TUBUH BERSAMA DAN LUKIS", "ar": "اجلب الجسد المشترك وارسم"
        }
    ),
    (
        "", "TABLE EMPTY - BRING A BODY", "", "",
        {
            "zh-hans": "工作台为空 - 请先带来躯体", "zh-hant": "工作台為空 - 請先帶來軀體",
            "zh-cn": "工作台为空 - 请先带来躯体", "zh-tw": "工作台為空 - 請先帶來軀體",
            "ja": "作業台が空です - 体を持ってきてください", "ko": "작업대가 비어 있습니다 - 신체를 가져오세요",
            "es": "MESA VACÍA - TRAE UN CUERPO", "fr": "TABLE VIDE - APPORTEZ UN CORPS",
            "de": "TISCH LEER - BRINGE EINEN KÖRPER", "it": "TAVOLO VUOTO - PORTA UN CORPO",
            "pt": "MESA VAZIA - TRAGA UM CORPO", "ru": "СТОЛ ПУСТ - ПРИНЕСИТЕ ТЕЛО",
            "pl": "STÓŁ PUSTY - PRZYNIEŚ CIAŁO", "tr": "MASA BOŞ - BİR GÖVDE GETİR",
            "vi": "BÀN RỖNG - HÃY MANG THÂN THỂ ĐẾN", "th": "โต๊ะว่าง - โปรดนำร่างมา",
            "id": "MEJA KOSONG - BAWA TUBUH", "ar": "الطاولة فارغة - احضر جسدا"
        }
    ),
    (
        "", "POTION SHELF FULL - COLLECT A POTION", "", "",
        {
            "zh-hans": "药水架已满 - 请先领取药水", "zh-hant": "藥水架已滿 - 請先領取藥水",
            "zh-cn": "药水架已满 - 请先领取药水", "zh-tw": "藥水架已滿 - 請先領取藥水",
            "ja": "ポーション棚が満杯です - ポーションを回収してください", "ko": "포션 선반이 가득 찼습니다 - 포션을 수령하세요",
            "es": "ESTANTE LLENO - RECOGE UNA POCIÓN", "fr": "ÉTAGÈRE PLEINE - RÉCUPÉREZ UNE POTION",
            "de": "TRANKREGAL VOLL - NIMM EINEN TRANK", "it": "SCAFFALE PIENO - PRENDI UNA POZIONE",
            "pt": "PRATELEIRA CHEIA - PEGUE UMA POÇÃO", "ru": "ПОЛКА ПОЛНА - ЗАБЕРИТЕ ЗЕЛЬЕ",
            "pl": "PÓŁKA PEŁNA - ODBIERZ MIKSTURĘ", "tr": "İKSİR RAFI DOLU - BİR İKSİR AL",
            "vi": "GIÁ ĐÃ ĐẦY - HÃY LẤY THUỐC", "th": "ชั้นวางเต็ม - เก็บยาออกไป",
            "id": "RAK PENUH - AMBIL RAMUAN", "ar": "الرف ممتلئ - خذ جرعة"
        }
    ),
    (
        "", "ALTAR BUSY - WAIT FOR CONVERSION", "", "",
        {
            "zh-hans": "祭坛忙碌中 - 请等待转化完成", "zh-hant": "祭壇忙碌中 - 請等待轉化完成",
            "zh-cn": "祭坛忙碌中 - 请等待转化完成", "zh-tw": "祭壇忙碌中 - 請等待轉化完成",
            "ja": "祭壇は使用中 - 変換をお待ちください", "ko": "제단 작동 중 - 변환을 기다리세요",
            "es": "ALTAR OCUPADO - ESPERA LA CONVERSIÓN", "fr": "AUTEL OCCUPÉ - ATTENDEZ LA CONVERSION",
            "de": "ALTAR BESCHÄFTIGT - WARTE AUF DIE UMWANDLUNG", "it": "ALTARE OCCUPATO - ATTENDI LA CONVERSIONE",
            "pt": "ALTAR OCUPADO - ESPERE A CONVERSÃO", "ru": "АЛТАРЬ ЗАНЯТ - ЖДИТЕ ПРЕОБРАЗОВАНИЯ",
            "pl": "OŁTARZ ZAJĘTY - ZACZEKAJ NA KONWERSJĘ", "tr": "SUNAK MEŞGUL - DÖNÜŞÜMÜ BEKLE",
            "vi": "BÀN THỜ ĐANG BẬN - HÃY CHỜ CHUYỂN HÓA", "th": "แท่นบูชาไม่ว่าง - รอการแปลงสภาพ",
            "id": "ALTAR SIBUK - TUNGGU KONVERSI", "ar": "المذبح مشغول - انتظر التحويل"
        }
    ),
    (
        "", "INSERT COMPLETED RUNE BODY", "", "",
        {
            "zh-hans": "投入已完成画符的躯体", "zh-hant": "投入已完成畫符的軀體",
            "zh-cn": "投入已完成画符的躯体", "zh-tw": "投入已完成畫符的軀體",
            "ja": "完成したルーンの体を投入", "ko": "완성된 룬 신체 투입",
            "es": "INSERTAR CUERPO RÚNICO COMPLETADO", "fr": "INSÉRER LE CORPS RUNIQUE TERMINÉ",
            "de": "FERTIGEN RUNENKÖRPER EINLEGEN", "it": "INSERISCI IL CORPO RUNICO COMPLETATO",
            "pt": "INSERIR CORPO RÚNICO CONCLUÍDO", "ru": "ВЛОЖИТЬ ГОТОВОЕ РУНИЧЕСКОЕ ТЕЛО",
            "pl": "WŁÓŻ DOKOŃCZONE CIAŁO RUNICZNE", "tr": "TAMAMLANMIŞ RÜNLÜ GÖVDESİNİ YERLEŞTİR",
            "vi": "ĐƯA THÂN THỂ PHÙ VĂN HOÀN THÀNH VÀO", "th": "ใส่ร่างรูนที่เสร็จสมบูรณ์",
            "id": "MASUKKAN TUBUH RUNE YANG SELESAI", "ar": "أدخل جسد الرون المكتمل"
        }
    ),
    (
        "", "ALTAR NEEDS A COMPLETED RUNE BODY", "", "",
        {
            "zh-hans": "祭坛需要投入画完符文的躯体", "zh-hant": "祭壇需要投入畫完符文的軀體",
            "zh-cn": "祭坛需要投入画完符文的躯体", "zh-tw": "祭壇需要投入畫完符文的軀體",
            "ja": "祭壇には完成したルーンの体が必要です", "ko": "제단에는 완성된 룬 신체가 필요합니다",
            "es": "EL ALTAR NECESITA UN CUERPO RÚNICO COMPLETADO", "fr": "L'AUTEL A BESOIN D'UN CORPS RUNIQUE TERMINÉ",
            "de": "DER ALTAR BRAUCHT EINEN FERTIGEN RUNENKÖRPER", "it": "L'ALTARE RICHIEDE UN CORPO RUNICO COMPLETATO",
            "pt": "O ALTAR PRECISA DE UM CORPO RÚNICO CONCLUÍDO", "ru": "ДЛЯ АЛТАРЯ ТРЕБУЕТСЯ ГОТОВОЕ РУНИЧЕСКОЕ ТЕЛО",
            "pl": "OŁTARZ WYMAGA DOKOŃCZONEGO CIAŁA RUNICZNEGO", "tr": "SUNAĞA TAMAMLANMIŞ BİR RÜNLÜ GÖVDE LAZIM",
            "vi": "BÀN THỜ CẦN THÂN THỂ PHÙ VĂN HOÀN THÀNH", "th": "แท่นบูชาต้องการร่างรูนที่เสร็จแล้ว",
            "id": "ALTAR MEMBUTUHKAN TUBUH RUNE YANG SELESAI", "ar": "يحتاج المذبح إلى جسد رون مكتمل"
        }
    ),
    (
        "", "HANDS FULL - PUT DOWN YOUR ITEM", "", "",
        {
            "zh-hans": "双手已满 - 请先放下手中物品", "zh-hant": "雙手已滿 - 請先放下手中物品",
            "zh-cn": "双手已满 - 请先放下手中物品", "zh-tw": "雙手已滿 - 請先放下手中物品",
            "ja": "手が塞がっています - アイテムを置いてください", "ko": "손이 가득 찼습니다 - 물건을 내려놓으세요",
            "es": "MANOS LLENAS - DEJA TU OBJETO", "fr": "MAINS PLEINES - DÉPOSEZ VOTRE OBJET",
            "de": "HÄNDE VOLL - LEGE DEINEN GEGENSTAND AB", "it": "MANI OCCUPATE - POSA IL TUO OGGETTO",
            "pt": "MÃOS CHEIAS - LARGUE SEU ITEM", "ru": "РУКИ ЗАНЯТЫ - ПОЛОЖИТЕ ПРЕДМЕТ",
            "pl": "PEŁNE RĘCE - ODŁÓŻ PRZEDMIOT", "tr": "ELLERİN DOLU - EŞYANI BIRAK",
            "vi": "TAY ĐÃ ĐẦY - HÃY ĐẶT VẬT PHẨM XUỐNG", "th": "มือไม่ว่าง - วางไอเทมลงก่อน",
            "id": "TANGAN PENUH - LETAKKAN BARANGMU", "ar": "يديك ممتلئتان - ضع العنصر"
        }
    ),
    (
        "", "COLLECT READY POTION", "", "",
        {
            "zh-hans": "领取炼制好的药水", "zh-hant": "領取煉製好的藥水",
            "zh-cn": "领取炼制好的药水", "zh-tw": "領取煉製好的藥水",
            "ja": "完成したポーションを回収", "ko": "완성된 포션 수령",
            "es": "RECOGER POCIÓN LISTA", "fr": "RÉCUPÉRER LA POTION PRÊTE",
            "de": "FERTIGEN TRANK ABHOLEN", "it": "PRENDI LA POZIONE PRONTA",
            "pt": "PEGAR POÇÃO PRONTA", "ru": "ЗАБРАТЬ ГОТОВОЕ ЗЕЛЬЕ",
            "pl": "ODBIERZ GOTOWĄ MIKSTURĘ", "tr": "HAZIR İKSİRİ AL",
            "vi": "LẤY THUỐC ĐÃ SẴN SÀNG", "th": "เก็บยาที่พร้อมแล้ว",
            "id": "AMBIL RAMUAN YANG SIAP", "ar": "استلم الجرعة الجاهزة"
        }
    ),
    (
        "", "NO POTION READY - USE THE ALTAR FIRST", "", "",
        {
            "zh-hans": "尚无成品药水 - 请先使用祭坛转化", "zh-hant": "尚無成品藥水 - 請先使用祭壇轉化",
            "zh-cn": "尚无成品药水 - 请先使用祭坛转化", "zh-tw": "尚無成品藥水 - 請先使用祭壇轉化",
            "ja": "ポーションの準備ができていません - まず祭壇を使用してください",
            "ko": "준비된 포션이 없습니다 - 먼저 제단을 사용하세요",
            "es": "NO HAY POCIÓN LISTA - USA EL ALTAR PRIMERO",
            "fr": "AUCUNE POTION PRÊTE - UTILISEZ D'ABORD L'AUTEL",
            "de": "KEIN TRANK BEREIT - BENUTZE ZUERST DEN ALTAR",
            "it": "NESSUNA POZIONE PRONTA - USA PRIMA L'ALTARE",
            "pt": "NENHUMA POÇÃO PRONTA - USE O ALTAR PRIMEIRO",
            "ru": "НЕТ ГОТОВЫХ ЗЕЛИЙ - СНАЧАЛА ИСПОЛЬЗУЙТЕ АЛТАРЬ",
            "pl": "BRAK GOTOWYCH MIKSTUR - NAJPIERW UŻYJ OŁTARZA",
            "tr": "HAZIR İKSİR YOK - ÖNCE SUNAĞI KULLAN",
            "vi": "CHƯA CÓ THUỐC SẴN SÀNG - HÃY DÙNG BÀN THỜ TRƯỚC",
            "th": "ยังไม่มียาที่พร้อม - ใช้แท่นบูชาก่อน",
            "id": "TIDAK ADA RAMUAN SIAP - GUNAKAN ALTAR DAHULU",
            "ar": "لا توجد جرعة جاهزة - استخدم المذبح أولا"
        }
    ),
    (
        "", "EQUIP A POTION TO OFFER", "", "",
        {
            "zh-hans": "装备药水以进行提交", "zh-hant": "裝備藥水以進行提交",
            "zh-cn": "装备药水以进行提交", "zh-tw": "裝備藥水以進行提交",
            "ja": "捧げるポーションを装備してください", "ko": "바칠 포션을 장착하세요",
            "es": "EQUIPA UNA POCIÓN PARA OFRECER", "fr": "ÉQUIPEZ UNE POTION À OFFRIR",
            "de": "RÜSTE EINEN TRANK ZUM OPFERN AUS", "it": "EQUIPAGGIA UNA POZIONE DA OFFRIRE",
            "pt": "EQUIPE UMA POÇÃO PARA OFERECER", "ru": "ВОЗЬМИТЕ ЗЕЛЬЕ ДЛЯ ПОЖЕРТВОВАНИЯ",
            "pl": "WYPOSAŻ MIKSTURĘ, ABY JĄ OFIAROWAĆ", "tr": "SUNMAK İÇİN BİR İKSİR KUŞAN",
            "vi": "TRANG BỊ THUỐC ĐỂ DÂNG LÊN", "th": "ติดตั้งยาเพื่อถวาย",
            "id": "GUNAKAN RAMUAN UNTUK MEMPERSEMBAHKAN", "ar": "تزود بالجرعة لتقديمها"
        }
    ),
    (
        "", "BRING A POTION TO OFFER", "", "",
        {
            "zh-hans": "携带药水前来提交", "zh-hant": "攜帶藥水前來提交",
            "zh-cn": "携带药水前来提交", "zh-tw": "攜帶藥水前來提交",
            "ja": "捧げるポーションを持ってきてください", "ko": "바칠 포션을 가져오세요",
            "es": "TRAE UNA POCIÓN PARA OFRECER", "fr": "APPORTEZ UNE POTION À OFFRIR",
            "de": "BRINGE EINEN TRANK ZUM OPFERN", "it": "PORTA UNA POZIONE DA OFFRIRE",
            "pt": "TRAGA UMA POÇÃO PARA OFERECER", "ru": "ПРИНЕСИТЕ ЗЕЛЬЕ ДЛЯ ПОЖЕРТВОВАНИЯ",
            "pl": "PRZYNIEŚ MIKSTURĘ DO OFIAROWANIA", "tr": "SUNMAK İÇİN BİR İKSİR GETİR",
            "vi": "MANG THUỐC ĐẾN ĐỂ DÂNG LÊN", "th": "นำยามาเพื่อถวาย",
            "id": "BAWA RAMUAN UNTUK DIPERSEMBAHKAN", "ar": "احضر جرعة لتقديمها"
        }
    ),
    (
        "", "SHOULDER CARRY BODY", "", "",
        {
            "zh-hans": "肩扛躯体", "zh-hant": "肩扛軀體", "zh-cn": "肩扛躯体", "zh-tw": "肩扛軀體",
            "ja": "体を肩に担ぐ", "ko": "신체 어깨에 메기", "es": "LLEVAR CUERPO AL HOMBRO",
            "fr": "PORTER LE CORPS SUR L'ÉPAULE", "de": "KÖRPER AUF DER SCHULTER TRAGEN", "it": "PORTA IL CORPO IN SPALLA",
            "pt": "CARREGAR CORPO NO OMBRO", "ru": "НЕСТИ ТЕЛО НА ПЛЕЧЕ", "pl": "NIEŚ CIAŁO NA RAMIENIU",
            "tr": "GÖVDEYİ OMUZDA TAŞI", "vi": "VÁC THÂN THỂ LÊN VAI", "th": "แบกร่างบนไหล่",
            "id": "PIKUL TUBUH DI PUNDAK", "ar": "احمل الجسد على الكتف"
        }
    ),

    # --- 5. Hud & Combat (10 without args) ---
    (
        "", "ALTAR READY - SHELF FULL", "", "",
        {
            "zh-hans": "祭坛已就绪 - 药水架已满", "zh-hant": "祭壇已就緒 - 藥水架已滿",
            "zh-cn": "祭坛已就绪 - 药水架已满", "zh-tw": "祭壇已就緒 - 藥水架已滿",
            "ja": "祭壇完了 - 棚が満杯です", "ko": "제단 완료 - 선반 가득 참",
            "es": "ALTAR LISTO - ESTANTE LLENO", "fr": "AUTEL PRÊT - ÉTAGÈRE PLEINE",
            "de": "ALTAR BEREIT - REGAL VOLL", "it": "ALTARE PRONTO - SCAFFALE PIENO",
            "pt": "ALTAR PRONTO - PRATELEIRA CHEIA", "ru": "АЛТАРЬ ГОТОВ - ПОЛКА ПОЛНА",
            "pl": "OŁTARZ GOTOWY - PÓŁKA PEŁNA", "tr": "SUNAK HAZIR - RAF DOLU",
            "vi": "BÀN THỜ SẴN SÀNG - GIÁ ĐÃ ĐẦY", "th": "แท่นบูชาพร้อม - ชั้นวางเต็ม",
            "id": "ALTAR SIAP - RAK PENUH", "ar": "المذبح جاهز - الرف ممتلئ"
        }
    ),
    (
        "", "CARRYING POTION", "", "",
        {
            "zh-hans": "正搬运药水", "zh-hant": "正搬運藥水", "zh-cn": "正搬运药水", "zh-tw": "正搬運藥水",
            "ja": "ポーション運搬中", "ko": "포션 운반 중", "es": "LLEVANDO POCIÓN",
            "fr": "TRANSPORT D'UNE POTION", "de": "TRÄGT TRANK", "it": "TRASPORTO POZIONE",
            "pt": "CARREGANDO POÇÃO", "ru": "НЕСЕТ ЗЕЛЬЕ", "pl": "NIESIE MIKSTURĘ",
            "tr": "İKSİR TAŞINIYOR", "vi": "ĐANG MANG THUỐC", "th": "กำลังพกยา",
            "id": "MEMBAWA RAMUAN", "ar": "يحمل جرعة"
        }
    ),
    (
        "", "CARRYING RUNE BODY", "", "",
        {
            "zh-hans": "正搬运符文躯体", "zh-hant": "正搬運符文軀體", "zh-cn": "正搬运符文躯体", "zh-tw": "正搬運符文軀體",
            "ja": "ルーンの体を運搬中", "ko": "룬 신체 운반 중", "es": "LLEVANDO CUERPO RÚNICO",
            "fr": "TRANSPORT D'UN CORPS RUNIQUE", "de": "TRÄGT RUNENKÖRPER", "it": "TRASPORTO CORPO RUNICO",
            "pt": "CARREGANDO CORPO RÚNICO", "ru": "НЕСЕТ РУНИЧЕСКОЕ ТЕЛО", "pl": "NIESIE CIAŁO RUNICZNE",
            "tr": "RÜNLÜ GÖVDE TAŞINIYOR", "vi": "ĐANG MANG THÂN THỂ PHÙ VĂN", "th": "กำลังพกร่างรูน",
            "id": "MEMBAWA TUBUH RUNE", "ar": "يحمل جسد رون"
        }
    ),
    (
        "", "CARRYING BODY", "", "",
        {
            "zh-hans": "正搬运躯体", "zh-hant": "正搬運軀體", "zh-cn": "正搬运躯体", "zh-tw": "正搬運軀體",
            "ja": "体を運搬中", "ko": "신체 운반 중", "es": "LLEVANDO CUERPO",
            "fr": "TRANSPORT D'UN CORPS", "de": "TRÄGT KÖRPER", "it": "TRASPORTO CORPO",
            "pt": "CARREGANDO CORPO", "ru": "НЕСЕТ ТЕЛО", "pl": "NIESIE CIAŁO",
            "tr": "GÖVDE TAŞINIYOR", "vi": "ĐANG MANG THÂN THỂ", "th": "กำลังพกร่าง",
            "id": "MEMBAWA TUBUH", "ar": "يحمل جسدا"
        }
    ),
    (
        "", "HANDS EMPTY", "", "",
        {
            "zh-hans": "双手空闲", "zh-hant": "雙手空閒", "zh-cn": "双手空闲", "zh-tw": "雙手空閒",
            "ja": "手が空いています", "ko": "빈 손", "es": "MANOS VACÍAS",
            "fr": "MAINS VIDES", "de": "HÄNDE FREI", "it": "MANI LIBERE",
            "pt": "MÃOS VAZIAS", "ru": "РУКИ СВОБОДНЫ", "pl": "PUSTE RĘCE",
            "tr": "ELLER BOŞ", "vi": "TAY TRỐNG", "th": "มือว่าง",
            "id": "TANGAN KOSONG", "ar": "الأيدي فارغة"
        }
    ),
    (
        "", "HOLD AND DRAG TO PAINT AND ROTATE", "", "",
        {
            "zh-hans": "按住并拖动以旋转白膜并连续涂画",
            "zh-hant": "按住並拖曳以旋轉白膜並連續塗畫",
            "zh-cn": "按住并拖动以旋转白膜并连续涂画",
            "zh-tw": "按住並拖曳以旋轉白膜並連續塗畫",
            "ja": "長押し＆ドラッグで回転しながら連続描画",
            "ko": "길게 누르고 드래그하여 회전하며 연속으로 그리세요",
            "es": "MANTÉN Y ARRASTRA PARA PINTAR Y GIRAR",
            "fr": "MAINTENEZ ET GLISSEZ POUR PEINDRE ET PIVOTER",
            "de": "HALTEN UND ZIEHEN ZUM MALEN UND DREHEN",
            "it": "TIENI PREMUTO E TRASCINA PER DIPINGERE E RUOTARE",
            "pt": "SEGURE E ARRASTE PARA PINTAR E GIRAR",
            "ru": "УДЕРЖИВАЙТЕ И ВЕДИТЕ, ЧТОБЫ РИСОВАТЬ И ВРАЩАТЬ",
            "pl": "PRZYTRZYMAJ I PRZECIĄGNIJ, ABY MALOWAĆ I OBRACAĆ",
            "tr": "BOYAMAK VE DÖNDÜRMEK İÇİN BASILI TUTUP SÜRÜKLE",
            "vi": "NHẤN GIỮ VÀ KÉO ĐỂ VẼ VÀ XOAY",
            "th": "กดค้างแล้วลากเพื่อวาดและหมุน",
            "id": "TAHAN DAN GESER UNTUK MELUKIS DAN MEMUTAR",
            "ar": "اضغط مطولًا واسحب للرسم والتدوير"
        }
    ),
    (
        "", "HOLD AND DRAG TO PAINT RUNES", "", "",
        {
            "zh-hans": "按住并拖动以在躯体上绘制符文",
            "zh-hant": "按住並拖曳以在軀體上繪製符文",
            "zh-cn": "按住并拖动以在躯体上绘制符文",
            "zh-tw": "按住並拖曳以在軀體上繪製符文",
            "ja": "長押し＆ドラッグで体にルーンを描く",
            "ko": "길게 누르고 드래그하여 신체에 룬을 그리세요",
            "es": "MANTÉN Y ARRASTRA PARA PINTAR RUNAS",
            "fr": "MAINTENEZ ET GLISSEZ POUR PEINDRE LES RUNES",
            "de": "HALTEN UND ZIEHEN, UM RUNEN ZU MALEN",
            "it": "TIENI PREMUTO E TRASCINA PER DIPINGERE LE RUNE",
            "pt": "SEGURE E ARRASTE PARA PINTAR RUNAS",
            "ru": "УДЕРЖИВАЙТЕ И ВЕДИТЕ, ЧТОБЫ РИСОВАТЬ РУНЫ",
            "pl": "PRZYTRZYMAJ I PRZECIĄGNIJ, ABY MALOWAĆ RUNY",
            "tr": "RÜN ÇİZMEK İÇİN BASILI TUTUP SÜRÜKLE",
            "vi": "NHẤN GIỮ VÀ KÉO ĐỂ VẼ PHÙ VĂN",
            "th": "กดค้างแล้วลากเพื่อวาดรูน",
            "id": "TAHAN DAN GESER UNTUK MELUKIS RUNE",
            "ar": "اضغط مطولًا واسحب لرسم الرون"
        }
    ),
    (
        "", "TAKE TABLE BODY", "", "",
        {
            "zh-hans": "取走台面躯体", "zh-hant": "取走台面軀體", "zh-cn": "取走台面躯体", "zh-tw": "取走台面軀體",
            "ja": "作業台の体を回収", "ko": "작업대 신체 가져오기", "es": "TOMAR CUERPO DE LA MESA",
            "fr": "PRENDRE LE CORPS SUR LA TABLE", "de": "KÖRPER VOM TISCH NEHMEN", "it": "PRENDI IL CORPO DAL TAVOLO",
            "pt": "PEGAR CORPO DA MESA", "ru": "ВЗЯТЬ ТЕЛО СО СТОЛА", "pl": "WEŹ CIAŁO ZE STOŁU",
            "tr": "MASADAKİ GÖVDEYİ AL", "vi": "LẤY THÂN THỂ TRÊN BÀN", "th": "หยิบร่างบนโต๊ะ",
            "id": "AMBIL TUBUH DARI MEJA", "ar": "خذ جسد الطاولة"
        }
    ),
    (
        "", "DROP", "", "",
        {
            "zh-hans": "放下", "zh-hant": "放下", "zh-cn": "放下", "zh-tw": "放下",
            "ja": "落とす", "ko": "내려놓기", "es": "SOLTAR", "fr": "LÂCHER",
            "de": "FALLENLASSEN", "it": "LASCIA", "pt": "LARGAR", "ru": "БРОСИТЬ",
            "pl": "UPUŚĆ", "tr": "BIRAK", "vi": "THẢ XUỐNG", "th": "ปล่อย",
            "id": "JATUHKAN", "ar": "إسقاط"
        }
    ),
    (
        "", "STUNNED", "", "",
        {
            "zh-hans": "已击晕", "zh-hant": "已擊暈", "zh-cn": "已击晕", "zh-tw": "已擊暈",
            "ja": "気絶", "ko": "기절함", "es": "ATURDIDO", "fr": "ASSOMMÉ",
            "de": "BETÄUBT", "it": "STORDITO", "pt": "ATORDIDO", "ru": "ОГЛУШЕН",
            "pl": "OGŁUSZONY", "tr": "BAYGIN", "vi": "ĐÃ CHOÁNG", "th": "สตันแล้ว",
            "id": "PINGSAN", "ar": "مصعوق"
        }
    ),
    (
        "", "STUNNED - CARRY THE BODY", "", "",
        {
            "zh-hans": "已击晕 - 搬运躯体", "zh-hant": "已擊暈 - 搬運軀體", "zh-cn": "已击晕 - 搬运躯体", "zh-tw": "已擊暈 - 搬運軀體",
            "ja": "気絶 - 体を運んでください", "ko": "기절함 - 신체를 운반하세요",
            "es": "ATURDIDO - LLEVA EL CUERPO", "fr": "ASSOMMÉ - PORTEZ LE CORPS",
            "de": "BETÄUBT - TRAGE DEN KÖRPER", "it": "STORDITO - TRASPORTA IL CORPO",
            "pt": "ATORDIDO - CARREGUE O CORPO", "ru": "ОГЛУШЕН - НЕСИТЕ ТЕЛО",
            "pl": "OGŁUSZONY - PRZENIEŚ CIAŁO", "tr": "BAYGIN - GÖVDEYİ TAŞI",
            "vi": "ĐÃ CHOÁNG - HÃY MANG THÂN THỂ", "th": "สตันแล้ว - แบกร่างไป",
            "id": "PINGSAN - BAWA TUBUH", "ar": "مصعوق - احمل الجسد"
        }
    ),

    # --- 6. Notices (33 without args) ---
    (
        "", "The table is in use.", "", "",
        {
            "zh-hans": "工作台正在使用中。", "zh-hant": "工作台正在使用中。", "zh-cn": "工作台正在使用中。", "zh-tw": "工作台正在使用中。",
            "ja": "作業台は使用中です。", "ko": "작업대가 사용 중입니다.", "es": "La mesa está en uso.",
            "fr": "La table est utilisée.", "de": "Der Tisch wird benutzt.", "it": "Il tavolo è in uso.",
            "pt": "A mesa está em uso.", "ru": "Стол используется.", "pl": "Stół jest w użyciu.",
            "tr": "Masa kullanımda.", "vi": "Bàn đang được sử dụng.", "th": "โต๊ะกำลังถูกใช้งาน",
            "id": "Meja sedang digunakan.", "ar": "الطاولة قيد الاستخدام."
        }
    ),
    (
        "", "Store unfinished bodies here.", "", "",
        {
            "zh-hans": "此处仅存放未完成的躯体。", "zh-hant": "此處僅存放未完成的軀體。", "zh-cn": "此处仅存放未完成的躯体。", "zh-tw": "此處僅存放未完成的軀體。",
            "ja": "未完成の体はここに保管してください。", "ko": "미완성 신체는 여기에 보관하세요.", "es": "Guarda cuerpos incompletos aquí.",
            "fr": "Stockez les corps inachevés ici.", "de": "Lagere unfertige Körper hier.", "it": "Conserva i corpi incompleti qui.",
            "pt": "Guarde corpos incompletos aqui.", "ru": "Храните незавершенные тела здесь.", "pl": "Tutaj przechowuj niedokończone ciała.",
            "tr": "Tamamlanmamış gövdeleri buraya koy.", "vi": "Lưu trữ thân thể chưa hoàn thành tại đây.", "th": "จัดเก็บร่างที่ยังไม่เสร็จที่นี่",
            "id": "Simpan tubuh belum selesai di sini.", "ar": "خزن الأجساد غير المكتملة هنا."
        }
    ),
    (
        "", "The holding pool is full.", "", "",
        {
            "zh-hans": "存放池已满。", "zh-hant": "存放池已滿。", "zh-cn": "存放池已满。", "zh-tw": "存放池已滿。",
            "ja": "保管プールが満杯です。", "ko": "보관소가 가득 찼습니다.", "es": "El pozo de contención está lleno.",
            "fr": "Le bassin est plein.", "de": "Das Auffangbecken ist voll.", "it": "La vasca è piena.",
            "pt": "O poço de contenção está cheio.", "ru": "Пул хранения заполнен.", "pl": "Zbiornik jest pełny.",
            "tr": "Tutma havuzu dolu.", "vi": "Hồ chứa đã đầy.", "th": "บ่อกักเก็บเต็มแล้ว",
            "id": "Kolam penampungan penuh.", "ar": "حوض الاحتجاز ممتلئ."
        }
    ),
    (
        "", "The holding pool is empty.", "", "",
        {
            "zh-hans": "存放池为空。", "zh-hant": "存放池為空。", "zh-cn": "存放池为空。", "zh-tw": "存放池為空。",
            "ja": "保管プールが空です。", "ko": "보관소가 비어 있습니다.", "es": "El pozo de contención está vacío.",
            "fr": "Le bassin est vide.", "de": "Das Auffangbecken ist leer.", "it": "La vasca è vuota.",
            "pt": "O poço de contenção está vazio.", "ru": "Пул хранения пуст.", "pl": "Zbiornik jest pusty.",
            "tr": "Tutma havuzu boş.", "vi": "Hồ chứa trống rỗng.", "th": "บ่อกักเก็บว่างเปล่า",
            "id": "Kolam penampungan kosong.", "ar": "حوض الاحتجاز فارغ."
        }
    ),
    (
        "", "The table is occupied.", "", "",
        {
            "zh-hans": "工作台已被占用。", "zh-hant": "工作台已被佔用。", "zh-cn": "工作台已被占用。", "zh-tw": "工作台已被佔用。",
            "ja": "作業台は埋まっています。", "ko": "작업대가 차 있습니다.", "es": "La mesa está ocupada.",
            "fr": "La table est occupée.", "de": "Der Tisch ist belegt.", "it": "Il tavolo è occupato.",
            "pt": "A mesa está ocupada.", "ru": "Стол занят.", "pl": "Stół jest zajęty.",
            "tr": "Masa dolu.", "vi": "Bàn đã bị chiếm.", "th": "โต๊ะไม่ว่าง",
            "id": "Meja terisi.", "ar": "الطاولة مشغولة."
        }
    ),
    (
        "", "Bring an unfinished body.", "", "",
        {
            "zh-hans": "请带来未完成的躯体。", "zh-hant": "請帶來未完成的軀體。", "zh-cn": "请带来未完成的躯体。", "zh-tw": "請帶來未完成的軀體。",
            "ja": "未完成の体を持ってきてください。", "ko": "미완성 신체를 가져오세요.", "es": "Trae un cuerpo incompleto.",
            "fr": "Apportez un corps inachevé.", "de": "Bringe einen unfertigen Körper.", "it": "Porta un corpo incompleto.",
            "pt": "Traga um corpo incompleto.", "ru": "Принесите незавершенное тело.", "pl": "Przynieś niedokończone ciało.",
            "tr": "Tamamlanmamış bir gövde getir.", "vi": "Hãy mang thân thể chưa hoàn thành đến.", "th": "โปรดนำร่างที่ยังไม่เสร็จมา",
            "id": "Bawa tubuh yang belum selesai.", "ar": "احضر جسدا غير مكتمل."
        }
    ),
    (
        "", "Bring a stunned body or fill the pool.", "", "",
        {
            "zh-hans": "请带来已击晕的躯体或补充存放池。", "zh-hant": "請帶來已擊暈的軀體或補充存放池。", "zh-cn": "请带来已击晕的躯体或补充存放池。", "zh-tw": "請帶來已擊暈的軀體或補充存放池。",
            "ja": "気絶した体を持ってくるかプールを補充してください。", "ko": "기절한 신체를 가져오거나 보관소를 채우세요.",
            "es": "Trae un cuerpo aturdido o llena el pozo.", "fr": "Apportez un corps assommé ou remplissez le bassin.",
            "de": "Bringe einen betäubten Körper oder fülle das Becken.", "it": "Porta un corpo stordito o riempi la vasca.",
            "pt": "Traga um corpo atordoado ou encha o poço.", "ru": "Принесите оглушенное тело или наполните пул.",
            "pl": "Przynieś ogłuszone ciało lub napełnij zbiornik.", "tr": "Baygın bir gövde getir veya havuzu doldur.",
            "vi": "Hãy mang thân thể đã choáng đến hoặc nạp đầy hồ.", "th": "นำร่างที่สตันมาหรือเติมบ่อให้เต็ม",
            "id": "Bawa tubuh pingsan atau isi kolam.", "ar": "احضر جسدا مصعوقا أو املأ الحوض."
        }
    ),
    (
        "", "The altar is occupied.", "", "",
        {
            "zh-hans": "祭坛已被占用。", "zh-hant": "祭壇已被佔用。", "zh-cn": "祭坛已被占用。", "zh-tw": "祭壇已被佔用。",
            "ja": "祭壇は使用中です。", "ko": "제단이 차 있습니다.", "es": "El altar está ocupado.",
            "fr": "L'autel est occupé.", "de": "Der Altar ist belegt.", "it": "L'altare è occupato.",
            "pt": "O altar está ocupado.", "ru": "Алтарь занят.", "pl": "Ołtarz jest zajęty.",
            "tr": "Sunak dolu.", "vi": "Bàn thờ đã bị chiếm.", "th": "แท่นบูชาไม่ว่าง",
            "id": "Altar terisi.", "ar": "المذبح مشغول."
        }
    ),
    (
        "", "The altar needs a completed rune body.", "", "",
        {
            "zh-hans": "祭坛需要已完成画符的躯体。", "zh-hant": "祭壇需要已完成畫符的軀體。", "zh-cn": "祭坛需要已完成画符的躯体。", "zh-tw": "祭壇需要已完成畫符的軀體。",
            "ja": "祭壇には完成したルーンの体が必要です。", "ko": "제단에는 완성된 룬 신체가 필요합니다.", "es": "El altar necesita un cuerpo rúnico completado.",
            "fr": "L'autel a besoin d'un corps runique terminé.", "de": "Der Altar braucht einen fertigen Runenkörper.", "it": "L'altare richiede un corpo runico completato.",
            "pt": "O altar precisa de um corpo rúnico concluído.", "ru": "Для алтаря требуется готовое руническое тело.", "pl": "Ołtarz wymaga dokończonego ciała runicznego.",
            "tr": "Sunağa tamamlanmış bir rünlü gövde lazım.", "vi": "Bàn thờ cần thân thể phù văn hoàn chỉnh.", "th": "แท่นบูชาต้องการร่างรูนที่เสร็จสมบูรณ์",
            "id": "Altar membutuhkan tubuh rune yang selesai.", "ar": "يحتاج المذبح إلى جسد رون مكتمل."
        }
    ),
    (
        "", "Your hands are full.", "", "",
        {
            "zh-hans": "你的双手已满。", "zh-hant": "你的雙手已滿。", "zh-cn": "你的双手已满。", "zh-tw": "你的雙手已滿。",
            "ja": "手が塞がっています。", "ko": "손이 가득 찼습니다.", "es": "Tus manos están llenas.",
            "fr": "Vos mains sont pleines.", "de": "Deine Hände sind voll.", "it": "Le tue mani sono occupate.",
            "pt": "Suas mãos estão cheias.", "ru": "Ваши руки заняты.", "pl": "Masz pełne ręce.",
            "tr": "Ellerin dolu.", "vi": "Hai tay của bạn đã đầy.", "th": "มือของคุณเต็มแล้ว",
            "id": "Tanganmu penuh.", "ar": "يديك ممتلئتان."
        }
    ),
    (
        "", "No potions are ready.", "", "",
        {
            "zh-hans": "尚无药水准备就绪。", "zh-hant": "尚無藥水準備就緒。", "zh-cn": "尚无药水准备就绪。", "zh-tw": "尚無藥水準備就緒。",
            "ja": "準備のできたポーションはありません。", "ko": "준비된 포션이 없습니다.", "es": "No hay pociones listas.",
            "fr": "Aucune potion n'est prête.", "de": "Keine Tränke bereit.", "it": "Nessuna pozione è pronta.",
            "pt": "Nenhuma poção está pronta.", "ru": "Нет готовых зелий.", "pl": "Brak gotowych mikstur.",
            "tr": "Hazırda iksir yok.", "vi": "Chưa có thuốc sẵn sàng.", "th": "ยังไม่มียาที่พร้อม",
            "id": "Belum ada ramuan yang siap.", "ar": "لا توجد جرعات جاهزة."
        }
    ),
    (
        "", "Bring a potion to the summoning sigil.", "", "",
        {
            "zh-hans": "请将药水带往召唤法阵。", "zh-hant": "請將藥水帶往召喚法陣。", "zh-cn": "请将药水带往召唤法阵。", "zh-tw": "請將藥水帶往召喚法陣。",
            "ja": "ポーションを召喚陣へ持ってきてください。", "ko": "포션을 소환진으로 가져오세요.", "es": "Lleva una poción al círculo de invocación.",
            "fr": "Apportez une potion au cercle d'invocation.", "de": "Bringe einen Trank zum Beschwörungssiegel.", "it": "Porta una pozione al sigillo di evocazione.",
            "pt": "Traga uma poção para o símbolo de invocação.", "ru": "Отнесите зелье к сигилу призыва.", "pl": "Zanieś miksturę do symbolu przywołania.",
            "tr": "Çağırma mührüne bir iksir getir.", "vi": "Hãy mang thuốc đến vòng phù hiệu triệu hồi.", "th": "นำยาไปที่สัญลักษณ์อัญเชิญ",
            "id": "Bawa ramuan ke segel pemanggilan.", "ar": "احضر جرعة إلى ختم الاستدعاء."
        }
    ),
    (
        "", "Coin limit reached.", "", "",
        {
            "zh-hans": "金币已达上限。", "zh-hant": "金幣已達上限。", "zh-cn": "金币已达上限。", "zh-tw": "金幣已達上限。",
            "ja": "コインの上限に達しました。", "ko": "코인 한도에 도달했습니다.", "es": "Límite de monedas alcanzado.",
            "fr": "Limite de pièces atteinte.", "de": "Münzlimit erreicht.", "it": "Limite di monete raggiunto.",
            "pt": "Limite de moedas atingido.", "ru": "Достигнут лимит монет.", "pl": "Osiągnięto limit monet.",
            "tr": "Jeton sınırına ulaşıldı.", "vi": "Đã đạt giới hạn xu.", "th": "ถึงขีดจำกัดเหรียญแล้ว",
            "id": "Batas koin tercapai.", "ar": "تم الوصول إلى حد العملات."
        }
    ),
    (
        "", "Rune complete. The body flies to the altar.", "", "",
        {
            "zh-hans": "符文绘制完成，躯体飞向祭坛。", "zh-hant": "符文繪製完成，軀體飛向祭壇。", "zh-cn": "符文绘制完成，躯体飞向祭坛。", "zh-tw": "符文繪製完成，軀體飛向祭壇。",
            "ja": "ルーン完了。体が祭壇へ飛びます。", "ko": "룬 완성. 신체가 제단으로 날아갑니다.", "es": "Runa completada. El cuerpo vuela hacia el altar.",
            "fr": "Rune terminée. Le corps vole vers l'autel.", "de": "Rune vollständig. Der Körper fliegt zum Altar.", "it": "Runa completata. Il corpo vola verso l'altare.",
            "pt": "Runa concluída. O corpo voa para o altar.", "ru": "Руна завершена. Тело летит к алтарю.", "pl": "Runa ukończona. Ciało leci do ołtarza.",
            "tr": "Rün tamamlandı. Gövde sunağa uçuyor.", "vi": "Phù văn hoàn tất. Thân thể bay về phía bàn thờ.", "th": "รูนเสร็จสมบูรณ์ ร่างกำลังลอยไปยังแท่นบูชา",
            "id": "Rune selesai. Tubuh terbang menuju altar.", "ar": "اكتمل الرون. يطير الجسد إلى المذبح."
        }
    ),
    (
        "", "Station changed. Try interacting again.", "", "",
        {
            "zh-hans": "工位状态已改变，请重试交互。", "zh-hant": "工位狀態已改變，請重試交互。", "zh-cn": "工位状态已改变，请重试交互。", "zh-tw": "工位狀態已改變，請重試交互。",
            "ja": "ステーションが変更されました。もう一度操作してください。", "ko": "작업대 상태가 변경되었습니다. 다시 상호작용하세요.",
            "es": "La estación cambió. Intenta interactuar de nuevo.", "fr": "La station a changé. Réessayez d'interagir.",
            "de": "Station geändert. Versuche erneut zu interagieren.", "it": "La stazione è cambiata. Prova a interagire di nuovo.",
            "pt": "A estação mudou. Tente interagir novamente.", "ru": "Станция изменилась. Попробуйте взаимодействовать снова.",
            "pl": "Stacja się zmieniła. Spróbuj wejść w interakcję ponownie.", "tr": "İstasyon değişti. Tekrar etkileşime geçmeyi dene.",
            "vi": "Khu vực làm việc đã thay đổi. Hãy thử tương tác lại.", "th": "สถานีเปลี่ยนไป ลองโต้ตอบใหม่อีกครั้ง",
            "id": "Stasiun berubah. Coba berinteraksi lagi.", "ar": "تغيرت المحطة. حاول التفاعل مرة أخرى."
        }
    ),
    (
        "", "Move closer with a clear path to the station.", "", "",
        {
            "zh-hans": "距离工位过远或被遮挡，请靠近重试。", "zh-hant": "距離工位過遠或被遮擋，請靠近重試。", "zh-cn": "距离工位过远或被遮挡，请靠近重试。", "zh-tw": "距離工位過遠或被遮擋，請靠近重試。",
            "ja": "ステーションに近づいて遮るもののない位置からお試しください。", "ko": "작업대에 더 가까이 이동하고 경로를 확보하세요.",
            "es": "Acércate con un camino despejado a la estación.", "fr": "Rapprochez-vous avec un chemin dégagé vers la station.",
            "de": "Gehe näher heran mit freiem Weg zur Station.", "it": "Avvicinati con un percorso libero verso la stazione.",
            "pt": "Aproxime-se com um caminho livre para a estação.", "ru": "Подойдите ближе, освободив путь к станции.",
            "pl": "Podejdź bliżej z wolną drogą do stacji.", "tr": "İstasyona açık bir yolla yaklaş.",
            "vi": "Tiến lại gần hơn với đường đi thông thoáng đến khu vực.", "th": "ขยับเข้าไปใกล้พร้อมเปิดทางโล่งไปยังสถานี",
            "id": "Mendekatlah dengan jalur yang jelas ke stasiun.", "ar": "اقترب بمسار واضح إلى المحطة."
        }
    ),
    (
        "", "Item changed or was taken. Choose it again.", "", "",
        {
            "zh-hans": "物品状态改变或已被取走，请重新选择。", "zh-hant": "物品狀態改變或已被取走，請重新選擇。", "zh-cn": "物品状态改变或已被取走，请重新选择。", "zh-tw": "物品狀態改變或已被取走，請重新選擇。",
            "ja": "アイテムの状態が変化したか回収されました。再度選んでください。", "ko": "아이템이 변경되었거나 이동되었습니다. 다시 선택하세요.",
            "es": "El objeto cambió o fue tomado. Elígelo de nuevo.", "fr": "L'objet a changé ou a été pris. Choisissez-le à nouveau.",
            "de": "Gegenstand geändert oder genommen. Wähle ihn erneut.", "it": "L'oggetto è cambiato o è stato preso. Selezionalo di nuovo.",
            "pt": "O item mudou ou foi pego. Escolha-o novamente.", "ru": "Предмет изменился или был взят. Выберите снова.",
            "pl": "Przedmiot zmienił się lub został zabrany. Wybierz go ponownie.", "tr": "Eşya değişti veya alındı. Yeniden seç.",
            "vi": "Vật phẩm đã thay đổi hoặc đã bị lấy mất. Hãy chọn lại.", "th": "ไอเทมเปลี่ยนไปหรือถูกหยิบไปแล้ว เลือกใหม่อีกครั้ง",
            "id": "Barang berubah atau telah diambil. Pilih lagi.", "ar": "تغير العنصر أو تم أخذه. اختره مرة أخرى."
        }
    ),
    (
        "", "Move closer with a clear path to the item.", "", "",
        {
            "zh-hans": "距离物品过远或被遮挡，请靠近重试。", "zh-hant": "距離物品過遠或被遮擋，請靠近重試。", "zh-cn": "距离物品过远或被遮挡，请靠近重试。", "zh-tw": "距離物品過遠或被遮擋，請靠近重試。",
            "ja": "アイテムに近づいて遮るもののない位置からお試しください。", "ko": "아이템에 더 가까이 이동하고 경로를 확보하세요.",
            "es": "Acércate con un camino despejado al objeto.", "fr": "Rapprochez-vous avec un chemin dégagé vers l'objet.",
            "de": "Gehe näher heran mit freiem Weg zum Gegenstand.", "it": "Avvicinati con un percorso libero verso l'oggetto.",
            "pt": "Aproxime-se com um caminho livre para o item.", "ru": "Подойдите ближе, освободив путь к предмету.",
            "pl": "Podejdź bliżej z wolną drogą do przedmiotu.", "tr": "Eşyaya açık bir yolla yaklaş.",
            "vi": "Tiến lại gần hơn với đường đi thông thoáng đến vật phẩm.", "th": "ขยับเข้าไปใกล้พร้อมเปิดทางโล่งไปยังไอเทม",
            "id": "Mendekatlah dengan jalur yang jelas ke barang.", "ar": "اقترب بمسار واضح إلى العنصر."
        }
    ),
    (
        "", "This item is occupied or cannot be carried yet.", "", "",
        {
            "zh-hans": "物品已被占用或暂不可搬运。", "zh-hant": "物品已被佔用或暫不可搬運。", "zh-cn": "物品已被占用或暂不可搬运。", "zh-tw": "物品已被佔用或暫不可搬運。",
            "ja": "このアイテムは使用中またはまだ運搬できません。", "ko": "이 아이템은 사용 중이거나 아직 운반할 수 없습니다.",
            "es": "Este objeto está ocupado o aún no se puede llevar.", "fr": "Cet objet est occupé ou ne peut pas encore être porté.",
            "de": "Dieser Gegenstand ist besetzt oder kann noch nicht getragen werden.", "it": "Questo oggetto è occupato o non può essere ancora trasportato.",
            "pt": "Este item está ocupado ou ainda não pode ser carregado.", "ru": "Этот предмет занят или его пока нельзя нести.",
            "pl": "Ten przedmiot jest zajęty lub nie można go jeszcze przenieść.", "tr": "Bu eşya kullanımda veya henüz taşınamaz.",
            "vi": "Vật phẩm này đang bận hoặc chưa thể mang đi.", "th": "ไอเทมนี้ถูกใช้งานอยู่หรือไม่สามารถถือได้ในขณะนี้",
            "id": "Barang ini terpakai atau belum bisa dibawa.", "ar": "هذا العنصر مشغول أو لا يمكن حمله بعد."
        }
    ),
    (
        "", "Paint batch out of sequence.", "", "",
        {
            "zh-hans": "笔迹批次序号不连续。", "zh-hant": "筆跡批次序號不連續。", "zh-cn": "笔迹批次序号不连续。", "zh-tw": "筆跡批次序號不連續。",
            "ja": "ペイントのバッチ順序が正しくありません。", "ko": "페인트 배치 순서가 맞지 않습니다.", "es": "Lote de pintura fuera de secuencia.",
            "fr": "Lot de peinture hors séquence.", "de": "Malstapel außerhalb der Reihenfolge.", "it": "Lotto di pittura fuori sequenza.",
            "pt": "Lote de pintura fora de sequência.", "ru": "Пакет рисования нарушил последовательность.", "pl": "Partia malowania poza kolejnością.",
            "tr": "Boya grubu sıra dışı.", "vi": "Đợt vẽ không theo thứ tự.", "th": "ชุดระบายสีผิดลำดับ",
            "id": "Urutan cat tidak sesuai.", "ar": "دفعة الطلاء خارج التسلسل."
        }
    ),
    (
        "", "Paint upload rate exceeded.", "", "",
        {
            "zh-hans": "笔迹上传频率超限。", "zh-hant": "筆跡上傳頻率超限。", "zh-cn": "笔迹上传频率超限。", "zh-tw": "筆跡上傳頻率超限。",
            "ja": "ペイントのアップロード速度が上限を超過しました。", "ko": "페인트 업로드 속도가 초과되었습니다.", "es": "Tasa de subida de pintura superada.",
            "fr": "Fréquence d'envoi de peinture dépassée.", "de": "Mal-Upload-Rate überschritten.", "it": "Velocità di caricamento pittura superata.",
            "pt": "Taxa de envio de pintura excedida.", "ru": "Превышена частота отправки рисования.", "pl": "Przekroczono limit wysyłania malowania.",
            "tr": "Boya yükleme hızı aşıldı.", "vi": "Tần suất tải lên nét vẽ vượt quá giới hạn.", "th": "อัตราการอัปโหลดระบายสีเกินขีดจำกัด",
            "id": "Batas unggah cat terlampaui.", "ar": "تجاوز معدل تحميل الطلاء الحد."
        }
    ),
    (
        "", "Invalid paint body part.", "", "",
        {
            "zh-hans": "无效的绘制身体部位。", "zh-hant": "無效的繪製身體部位。", "zh-cn": "无效的绘制身体部位。", "zh-tw": "無效的繪製身體部位。",
            "ja": "無効な描画部位です。", "ko": "잘못된 페인트 신체 부위입니다.", "es": "Parte del cuerpo de pintura no válida.",
            "fr": "Partie du corps à peindre non valide.", "de": "Ungültiger Körperteil zum Malen.", "it": "Parte del corpo non valida per la pittura.",
            "pt": "Parte do corpo inválida para pintura.", "ru": "Неверная часть тела для рисования.", "pl": "Nieprawidłowa część ciała do malowania.",
            "tr": "Geçersiz boyama gövde parçası.", "vi": "Bộ phận thân thể vẽ không hợp lệ.", "th": "ส่วนของร่างที่ไม่ถูกต้องสำหรับการระบายสี",
            "id": "Bagian tubuh cat tidak valid.", "ar": "جزء الجسد المراد طلاؤه غير صالح."
        }
    ),
    (
        "", "Paint surface version mismatch.", "", "",
        {
            "zh-hans": "绘制表面版本不匹配。", "zh-hant": "繪製表面版本不匹配。", "zh-cn": "绘制表面版本不匹配。", "zh-tw": "繪製表面版本不匹配。",
            "ja": "描画サーフェスのバージョンが一致しません。", "ko": "페인트 표면 버전이 일치하지 않습니다.", "es": "Versión de superficie de pintura incompatible.",
            "fr": "Version de surface de peinture incompatible.", "de": "Version der Maloberfläche stimmt nicht überein.", "it": "Versione superficie di pittura non corrispondente.",
            "pt": "Versão da superfície de pintura incompatível.", "ru": "Несоответствие версии поверхности рисования.", "pl": "Niezgodność wersji powierzchni malowania.",
            "tr": "Boya yüzey sürümü uyuşmazlığı.", "vi": "Phiên bản bề mặt vẽ không khớp.", "th": "เวอร์ชันพื้นผิวระบายสีไม่ตรงกัน",
            "id": "Versi permukaan cat tidak cocok.", "ar": "عدم تطابق إصدار سطح الطلاء."
        }
    ),
    (
        "", "Paint upload rejected.", "", "",
        {
            "zh-hans": "笔迹上传被拒绝。", "zh-hant": "筆跡上傳被拒絕。", "zh-cn": "笔迹上传被拒绝。", "zh-tw": "筆跡上傳被拒絕。",
            "ja": "ペイントのアップロードが拒否されました。", "ko": "페인트 업로드가 거부되었습니다.", "es": "Subida de pintura rechazada.",
            "fr": "Envoi de peinture rejeté.", "de": "Mal-Upload abgelehnt.", "it": "Caricamento pittura rifiutato.",
            "pt": "Envio de pintura rejeitado.", "ru": "Загрузка рисования отклонена.", "pl": "Wysyłanie malowania odrzucone.",
            "tr": "Boya yüklemesi reddedildi.", "vi": "Tải lên nét vẽ bị từ chối.", "th": "การอัปโหลดระบายสีถูกปฏิเสธ",
            "id": "Unggahan cat ditolak.", "ar": "تم رفض تحميل الطلاء."
        }
    ),
    (
        "", "Invalid visual segment.", "", "",
        {
            "zh-hans": "无效的可视笔段数据。", "zh-hant": "無效的可視筆段數據。", "zh-cn": "无效的可视笔段数据。", "zh-tw": "無效的可視筆段數據。",
            "ja": "無効な視覚セグメントです。", "ko": "잘못된 시각 세그먼트입니다.", "es": "Segmento visual no válido.",
            "fr": "Segment visuel non valide.", "de": "Ungültiges visuelles Segment.", "it": "Segmento visivo non valido.",
            "pt": "Segmento visual inválido.", "ru": "Неверный визуальный сегмент.", "pl": "Nieprawidłowy segment wizualny.",
            "tr": "Geçersiz görsel bölüm.", "vi": "Phân đoạn hình ảnh không hợp lệ.", "th": "ส่วนของภาพไม่ถูกต้อง",
            "id": "Segmen visual tidak valid.", "ar": "شريحة بصرية غير صالحة."
        }
    ),
    (
        "", "Duplicate visual segment in batch.", "", "",
        {
            "zh-hans": "批次包含重复笔段。", "zh-hant": "批次包含重複筆段。", "zh-cn": "批次包含重复笔段。", "zh-tw": "批次包含重複筆段。",
            "ja": "バッチ内に重複した視覚セグメントがあります。", "ko": "배치에 중복된 시각 세그먼트가 있습니다.", "es": "Segmento visual duplicado en el lote.",
            "fr": "Segment visuel en double dans le lot.", "de": "Doppeltes visuelles Segment im Stapel.", "it": "Segmento visivo duplicato nel lotto.",
            "pt": "Segmento visual duplicado no lote.", "ru": "Повторяющийся визуальный сегмент в пакете.", "pl": "Zduplikowany segment wizualny w partii.",
            "tr": "Grupta yinelenen görsel bölüm.", "vi": "Phân đoạn hình ảnh bị trùng trong đợt.", "th": "มีส่วนของภาพซ้ำในชุด",
            "id": "Segmen visual duplikat dalam tumpukan.", "ar": "شريحة بصرية مكررة في الدفعة."
        }
    ),
    (
        "", "Segment origin changed.", "", "",
        {
            "zh-hans": "笔段起点改变。", "zh-hant": "筆段起點改變。", "zh-cn": "笔段起点改变。", "zh-tw": "筆段起點改變。",
            "ja": "セグメントの原点が変更されました。", "ko": "세그먼트 원점이 변경되었습니다.", "es": "El origen del segmento cambió.",
            "fr": "L'origine du segment a changé.", "de": "Segmentursprung geändert.", "it": "L'origine del segmento è cambiata.",
            "pt": "A origem do segmento mudou.", "ru": "Начало сегмента изменилось.", "pl": "Początek segmentu zmienił się.",
            "tr": "Bölüm kaynağı değişti.", "vi": "Điểm gốc phân đoạn đã thay đổi.", "th": "จุดเริ่มต้นของส่วนเปลี่ยนไป",
            "id": "Titik asal segmen berubah.", "ar": "تغير أصل الشريحة."
        }
    ),
    (
        "", "Paint segment budget reached.", "", "",
        {
            "zh-hans": "笔段预算达到上限。", "zh-hant": "筆段預算達到上限。", "zh-cn": "笔段预算达到上限。", "zh-tw": "筆段預算達到上限。",
            "ja": "描画セグメントの予算上限に達しました。", "ko": "페인트 세그먼트 예산에 도달했습니다.", "es": "Límite de segmentos de pintura alcanzado.",
            "fr": "Budget de segments de peinture atteint.", "de": "Budget für Malsegmente erreicht.", "it": "Budget segmenti di pittura raggiunto.",
            "pt": "Orçamento de segmentos de pintura atingido.", "ru": "Достигнут лимит сегментов рисования.", "pl": "Osiągnięto limit segmentów malowania.",
            "tr": "Boya bölümü sınırına ulaşıldı.", "vi": "Đã đạt giới hạn phân đoạn vẽ.", "th": "ถึงงบประมาณส่วนของการระบายสีแล้ว",
            "id": "Batas segmen cat tercapai.", "ar": "تم الوصول إلى الحد المسموح به لشرائح الطلاء."
        }
    ),
    (
        "", "Paint sync failed. Please reconnect.", "", "",
        {
            "zh-hans": "笔迹同步失败，请重新连接。", "zh-hant": "筆跡同步失敗，請重新連接。", "zh-cn": "笔迹同步失败，请重新连接。", "zh-tw": "筆跡同步失敗，請重新連接。",
            "ja": "ペイント同期に失敗しました。再接続してください。", "ko": "페인트 동기화 실패. 다시 연결하세요.", "es": "Error de sincronización de pintura. Reconéctate.",
            "fr": "Échec de synchronisation de peinture. Veuillez vous reconnecter.", "de": "Mal-Synchronisation fehlgeschlagen. Bitte neu verbinden.", "it": "Sincronizzazione pittura non riuscita. Riconnettiti.",
            "pt": "Falha na sincronização da pintura. Reconecte-se.", "ru": "Ошибка синхронизации рисования. Переподключитесь.", "pl": "Błąd synchronizacji malowania. Połącz się ponownie.",
            "tr": "Boya senkronizasyonu başarısız. Lütfen tekrar bağlan.", "vi": "Đồng bộ nét vẽ thất bại. Vui lòng kết nối lại.", "th": "การซิงค์ระบายสีล้มเหลว โปรดเชื่อมต่อใหม่",
            "id": "Sinkronisasi cat gagal. Silakan sambungkan ulang.", "ar": "فشلت مزامنة الطلاء. يرجى إعادة الاتصال."
        }
    ),
    (
        "", "PAINT SURFACE UNAVAILABLE. PLEASE TRY AGAIN.", "", "",
        {
            "zh-hans": "绘制表面不可用，请重试。", "zh-hant": "繪製表面不可用，請重試。", "zh-cn": "绘制表面不可用，请重试。", "zh-tw": "繪製表面不可用，請重試。",
            "ja": "描画サーフェスを利用できません。もう一度お試しください。", "ko": "페인트 표면을 사용할 수 없습니다. 다시 시도하세요.",
            "es": "SUPERFICIE DE PINTURA NO DISPONIBLE. REINTENTA.", "fr": "SURFACE DE PEINTURE INDISPONIBLE. VEUILLEZ RÉESSAYER.",
            "de": "MALOBERFLÄCHE NICHT VERFÜGBAR. BITTE ERNEUT VERSUCHEN.", "it": "SUPERFICIE DI PITTURA NON DISPONIBILE. RIPROVA.",
            "pt": "SUPERFÍCIE DE PINTURA INDISPONÍVEL. TENTE NOVAMENTE.", "ru": "ПОВЕРХНОСТЬ ДЛЯ РИСОВАНИЯ НЕДОСТУПНА. ПОПРОБУЙТЕ СНОВА.",
            "pl": "POWIERZCHNIA DO MALOWANIA NIEDOSTĘPNA. SPRÓBUJ PONOWNIE.", "tr": "BOYAMA YÜZEYİ KULLANILAMIYOR. LÜTFEN TEKRAR DENE.",
            "vi": "BỀ MẶT VẼ KHÔNG KHẢ DỤNG. VUI LÒNG THỬ LẠI.", "th": "พื้นผิวการระบายสีไม่พร้อมใช้งาน โปรดลองอีกครั้ง",
            "id": "PERMUKAAN CAT TIDAK TERSEDIA. SILAKAN COBA LAGI.", "ar": "سطح الطلاء غير متاح. يرجى المحاولة مرة أخرى."
        }
    ),
    (
        "", "PAINT SEGMENT LIMIT REACHED", "", "",
        {
            "zh-hans": "已达到画笔笔段上限。", "zh-hant": "已達到畫筆筆段上限。", "zh-cn": "已达到画笔笔段上限。", "zh-tw": "已達到畫筆筆段上限。",
            "ja": "描画セグメント数の上限に達しました。", "ko": "페인트 세그먼트 한도에 도달했습니다.", "es": "LÍMITE DE SEGMENTOS DE PINTURA ALCANZADO",
            "fr": "LIMITE DE SEGMENTS DE PEINTURE ATTEINTE", "de": "MALSEGMENT-LIMIT ERREICHT", "it": "LIMITE SEGMENTI DI PITTURA RAGGIUNTO",
            "pt": "LIMITE DE SEGMENTOS DE PINTURA ALCANÇADO", "ru": "ДОСТИГНУТ ЛИМИТ СЕГМЕНТОВ РИСОВАНИЯ", "pl": "OSIĄGNIĘTO LIMIT SEGMENTÓW MALOWANIA",
            "tr": "BOYA BÖLÜMÜ SINIRINA ULAŞILDI", "vi": "ĐÃ ĐẠT GIỚI HẠN PHÂN ĐOẠN VẼ", "th": "ถึงขีดจำกัดส่วนของการระบายสีแล้ว",
            "id": "BATAS SEGMEN CAT TERCAPAI", "ar": "تم الوصول إلى الحد الأقصى لشرائح الطلاء"
        }
    ),
    (
        "", "Unable to complete this action. Please try again.", "", "",
        {
            "zh-hans": "无法完成此操作，请重试。", "zh-hant": "無法完成此操作，請重試。", "zh-cn": "无法完成此操作，请重试。", "zh-tw": "無法完成此操作，請重試。",
            "ja": "このアクションを完了できませんでした。もう一度お試しください。", "ko": "이 작업을 완료할 수 없습니다. 다시 시도하세요.",
            "es": "No se pudo completar esta acción. Intenta de nuevo.", "fr": "Impossible de terminer cette action. Veuillez réessayer.",
            "de": "Aktion konnte nicht abgeschlossen werden. Bitte erneut versuchen.", "it": "Impossibile completare questa azione. Riprova.",
            "pt": "Não foi possível concluir esta ação. Tente novamente.", "ru": "Не удалось завершить действие. Попробуйте снова.",
            "pl": "Nie udało się ukończyć tej czynności. Spróbuj ponownie.", "tr": "Bu işlem tamamlanamadı. Lütfen tekrar dene.",
            "vi": "Không thể hoàn thành thao tác này. Vui lòng thử lại.", "th": "ไม่สามารถดำเนินการนี้ให้เสร็จสิ้นได้ โปรดลองอีกครั้ง",
            "id": "Tidak dapat menyelesaikan tindakan ini. Silakan coba lagi.", "ar": "تعذر إكمال هذا الإجراء. يرجى المحاولة مرة أخرى."
        }
    ),

    # --- 7. UI Static & Tool Names (11 items) ---
    (
        "", "SOUL WORKSHOP", "", "",
        {
            "zh-hans": "灵魂工坊", "zh-hant": "靈魂工坊", "zh-cn": "灵魂工坊", "zh-tw": "靈魂工坊",
            "ja": "魂の工房", "ko": "영혼 공방", "es": "TALLER DE ALMAS", "fr": "ATELIER DES ÂMES",
            "de": "SEELENWERKSTATT", "it": "LABORATORIO DELLE ANIME", "pt": "OFICINA DE ALMAS", "ru": "МАСТЕРСКАЯ ДУШ",
            "pl": "WARSZTAT DUSZ", "tr": "RUH ATÖLYESİ", "vi": "XƯỞNG LINH HỒN", "th": "โรงปฏิบัติการวิญญาณ",
            "id": "BENGKEL JIWA", "ar": "ورشة الأرواح"
        }
    ),
    (
        "", "DRAW THE RUNE", "", "",
        {
            "zh-hans": "绘制符文", "zh-hant": "繪製符文", "zh-cn": "绘制符文", "zh-tw": "繪製符文",
            "ja": "ルーンを描く", "ko": "룬 그리기", "es": "DIBUJA LA RUNA", "fr": "DESSINEZ LA RUNE",
            "de": "ZEICHNE DIE RUNE", "it": "DISEGNA LA RUNA", "pt": "DESENHE A RUNA", "ru": "НАРИСУЙТЕ РУНУ",
            "pl": "NARYSUJ RUNĘ", "tr": "RÜNÜ ÇİZ", "vi": "VẼ PHÙ VĂN", "th": "วาดรูน",
            "id": "GAMBAR RUNE", "ar": "ارسم الرون"
        }
    ),
    (
        "", "ATTACK", "", "",
        {
            "zh-hans": "攻击", "zh-hant": "攻擊", "zh-cn": "攻击", "zh-tw": "攻擊",
            "ja": "攻撃", "ko": "공격", "es": "ATACAR", "fr": "ATTAQUER",
            "de": "ANGREIFEN", "it": "ATTACCA", "pt": "ATACAR", "ru": "АТАКОВАТЬ",
            "pl": "ATAKUJ", "tr": "SALDIR", "vi": "TẤN CÔNG", "th": "โจมตี",
            "id": "SERANG", "ar": "هجوم"
        }
    ),
    (
        "", "HIT", "", "",
        {
            "zh-hans": "击打", "zh-hant": "擊打", "zh-cn": "击打", "zh-tw": "擊打",
            "ja": "攻撃", "ko": "타격", "es": "GOLPE", "fr": "FRAPPER",
            "de": "SCHLAGEN", "it": "COLPISCI", "pt": "GOLPEAR", "ru": "УДАР",
            "pl": "UDERZ", "tr": "VUR", "vi": "ĐÁNH", "th": "ตี",
            "id": "PUKUL", "ar": "ضرب"
        }
    ),
    (
        "", "RESET VIEW", "", "",
        {
            "zh-hans": "重置视角", "zh-hant": "重置視角", "zh-cn": "重置视角", "zh-tw": "重置視角",
            "ja": "視点リセット", "ko": "시점 초기화", "es": "RESTABLECER VISTA", "fr": "RÉINITIALISER LA VUE",
            "de": "ANSICHT ZURÜCKSETZEN", "it": "RIPRISTINA VISTA", "pt": "REDEFINIR VISÃO", "ru": "СБРОСИТЬ ВИД",
            "pl": "ZRESETUJ WIDOK", "tr": "GÖRÜNÜMÜ SIFIRLA", "vi": "ĐẶT LẠI GÓC NHÌN", "th": "รีเซ็ตมุมมอง",
            "id": "ATUR ULANG TAMPILAN", "ar": "إعادة ضبط المنظور"
        }
    ),
    (
        "", "RESET", "", "",
        {
            "zh-hans": "重置", "zh-hant": "重置", "zh-cn": "重置", "zh-tw": "重置",
            "ja": "リセット", "ko": "초기화", "es": "RESTABLECER", "fr": "RÉINITIALISER",
            "de": "ZURÜCKSETZEN", "it": "RIPRISTINA", "pt": "REDEFINIR", "ru": "СБРОС",
            "pl": "ZRESETUJ", "tr": "SIFIRLA", "vi": "ĐẶT LẠI", "th": "รีเซ็ต",
            "id": "ATUR ULANG", "ar": "إعادة ضبط"
        }
    ),
    (
        "", "EXIT", "", "",
        {
            "zh-hans": "退出", "zh-hant": "退出", "zh-cn": "退出", "zh-tw": "退出",
            "ja": "終了", "ko": "나가기", "es": "SALIR", "fr": "QUITTER",
            "de": "BEENDEN", "it": "ESCI", "pt": "SAIR", "ru": "ВЫЙТИ",
            "pl": "WYJDŹ", "tr": "ÇIKIŞ", "vi": "THOÁT", "th": "ออก",
            "id": "KELUAR", "ar": "خروج"
        }
    ),
    (
        "", "Club", "", "",
        {
            "zh-hans": "木棒", "zh-hant": "木棒", "zh-cn": "木棒", "zh-tw": "木棒",
            "ja": "棍棒", "ko": "몽둥이", "es": "Garrote", "fr": "Massue",
            "de": "Keule", "it": "Clava", "pt": "Clava", "ru": "Дубинка",
            "pl": "Pałka", "tr": "Sopa", "vi": "Gậy gỗ", "th": "ไม้กระบอง",
            "id": "Pentungan", "ar": "هراوة"
        }
    ),
    (
        "", "Brush", "", "",
        {
            "zh-hans": "画笔", "zh-hant": "畫筆", "zh-cn": "画笔", "zh-tw": "畫筆",
            "ja": "ブラシ", "ko": "붓", "es": "Pincel", "fr": "Pinceau",
            "de": "Pinsel", "it": "Pennello", "pt": "Pincel", "ru": "Кисть",
            "pl": "Pędzel", "tr": "Fırça", "vi": "Cọ vẽ", "th": "พู่กัน",
            "id": "Kuas", "ar": "فرشاة"
        }
    ),
    (
        "", "Tool", "", "",
        {
            "zh-hans": "工具", "zh-hant": "工具", "zh-cn": "工具", "zh-tw": "工具",
            "ja": "道具", "ko": "도구", "es": "Herramienta", "fr": "Outil",
            "de": "Werkzeug", "it": "Strumento", "pt": "Ferramenta", "ru": "Инструмент",
            "pl": "Narzędzie", "tr": "Alet", "vi": "Công cụ", "th": "เครื่องมือ",
            "id": "Alat", "ar": "أداة"
        }
    ),
    (
        "", "Function Description", "", "",
        {
            "zh-hans": "功能说明", "zh-hant": "功能說明", "zh-cn": "功能说明", "zh-tw": "功能說明",
            "ja": "機能説明", "ko": "기능 설명", "es": "Descripción de función", "fr": "Description de fonction",
            "de": "Funktionsbeschreibung", "it": "Descrizione della funzione", "pt": "Descrição da função", "ru": "Описание функции",
            "pl": "Opis funkcji", "tr": "İşlev Açıklaması", "vi": "Mô tả chức năng", "th": "คำอธิบายฟังก์ชัน",
            "id": "Deskripsi Fungsi", "ar": "وصف الوظيفة"
        }
    ),

    # --- 8. Station Plaques (3 items) ---
    (
        "", "SOUL ALTAR  /  10s", "", "",
        {
            "zh-hans": "灵魂祭坛  /  10秒", "zh-hant": "靈魂祭壇  /  10秒",
            "zh-cn": "灵魂祭坛  /  10秒", "zh-tw": "靈魂祭壇  /  10秒",
            "ja": "魂の祭壇  /  10秒", "ko": "영혼 제단  /  10초",
            "es": "ALTAR DE ALMAS  /  10s", "fr": "AUTEL DES ÂMES  /  10s",
            "de": "SEELENALTAR  /  10s", "it": "ALTARE DELLE ANIME  /  10s",
            "pt": "ALTAR DE ALMAS  /  10s", "ru": "АЛТАРЬ ДУШ  /  10с",
            "pl": "OŁTARZ DUSZ  /  10s", "tr": "RUH SUNAĞI  /  10sn",
            "vi": "BÀN THỜ LINH HỒN  /  10giây", "th": "แท่นบูชาวิญญาณ  /  10วินาที",
            "id": "ALTAR JIWA  /  10d", "ar": "مذبح الأرواح  /  10ث"
        }
    ),
    (
        "", "SOUL HOLDING POOL", "", "",
        {
            "zh-hans": "灵魂存放池", "zh-hant": "靈魂存放池",
            "zh-cn": "灵魂存放池", "zh-tw": "靈魂存放池",
            "ja": "魂の保管プール", "ko": "영혼 보관소",
            "es": "POZO DE ALMAS", "fr": "BASSIN DES ÂMES",
            "de": "SEELENBECKEN", "it": "VASCA DELLE ANIME",
            "pt": "POÇO DE ALMAS", "ru": "ПУЛ ДУШ",
            "pl": "ZBIORNIK DUSZ", "tr": "RUH HAVUZU",
            "vi": "HỒ LINH HỒN", "th": "บ่อเก็บวิญญาณ",
            "id": "KOLAM JIWA", "ar": "حوض الأرواح"
        }
    ),
    (
        "", "SOUL CRYSTALS", "", "",
        {
            "zh-hans": "灵魂药水架", "zh-hant": "靈魂藥水架",
            "zh-cn": "灵魂药水架", "zh-tw": "靈魂藥水架",
            "ja": "ソウルクリスタル", "ko": "영혼 수정",
            "es": "CRISTALES DE ALMA", "fr": "CRISTAUX D'ÂME",
            "de": "SEELENKRISTALLE", "it": "CRISTALLI DELL'ANIMA",
            "pt": "CRISTAIS DA ALMA", "ru": "КРИСТАЛЛЫ ДУШ",
            "pl": "KRYSZTAŁY DUSZ", "tr": "RUH KRİSTALLERİ",
            "vi": "TINH THỂ LINH HỒN", "th": "ผลึกวิญญาณ",
            "id": "KRISTAL JIWA", "ar": "بلورات الأرواح"
        }
    ),
]


def write_csv():
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        header = ["Key", "Context", "Example", "Source"] + LANGUAGES
        writer.writerow(header)
        for key, source, context, example, values in ENTRIES:
            row = [key, context, example, source]
            for lang in LANGUAGES:
                row.append(values.get(lang, values.get("zh-hans", source)))
            writer.writerow(row)
    print(f"Wrote {len(ENTRIES)} entries to {CSV_PATH}")


def write_sync_script():
    """Generate Luau script to set entries on LocalizationService.DemonShopLocalizationTable."""
    luau_entries = []
    for key, source, context, example, values in ENTRIES:
        val_parts = []
        # Support all target languages plus aliases zh-cn and zh-tw
        all_langs = sorted(list(values.keys()))
        for l in all_langs:
            v_escaped = values[l].replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
            val_parts.append(f'["{l}"] = "{v_escaped}"')
        vals_str = "{" + ", ".join(val_parts) + "}"
        k_escaped = key.replace('\\', '\\\\').replace('"', '\\"')
        s_escaped = source.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
        c_escaped = context.replace('\\', '\\\\').replace('"', '\\"')
        e_escaped = example.replace('\\', '\\\\').replace('"', '\\"')
        entry_code = f'\t{{\n\t\tKey = "{k_escaped}",\n\t\tSource = "{s_escaped}",\n\t\tContext = "{c_escaped}",\n\t\tExample = "{e_escaped}",\n\t\tValues = {vals_str},\n\t}}'
        luau_entries.append(entry_code)

    entries_code = ",\n".join(luau_entries)

    script_content = f"""--!strict
-- 自动同步 DemonShop 多语言本地化表 (全量覆写，清理历史旧农场词条)
assert(not game:GetService("RunService"):IsRunning(), "DemonShop Edit mode required")
local LocalizationService = game:GetService("LocalizationService")

local tableName = "DemonShopLocalizationTable"
local existingTable = LocalizationService:FindFirstChild(tableName)
local locTable: LocalizationTable
if existingTable and existingTable:IsA("LocalizationTable") then
\tlocTable = existingTable
else
\tlocal newTable = Instance.new("LocalizationTable")
\tnewTable.Name = tableName
\tnewTable.Parent = LocalizationService
\tlocTable = newTable
end

type Entry = {{
\tKey: string,
\tSource: string,
\tContext: string,
\tExample: string,
\tValues: {{ [string]: string }},
}}

local entries: {{ Entry }} = {{
{entries_code}
}}

local success, err = pcall(function()
\tlocTable:SetEntries(entries :: any)
end)

if not success then
\terror("Failed to set entries on " .. tableName .. ": " .. tostring(err))
end

-- 验证关键翻译器
local testLangs = {{ "zh-cn", "zh-tw", "zh-hans", "zh-hant", "ja", "ko", "es", "fr", "de", "pt", "ru" }}
local results: {{ [string]: string }} = {{}}
for _, lang in testLangs do
\tlocal translator = locTable:GetTranslator(lang)
\tif translator then
\t\tresults[lang] = translator:FormatByKey("Processing.Coins", {{ "100" }})
\telse
\t\tresults[lang] = "MISSING_TRANSLATOR"
\tend
end

return {{
\tstatus = "SUCCESS",
\ttotalEntries = #entries,
\ttestResults = results,
}}
"""
    LUAU_PATH.write_text(script_content, encoding="utf-8")
    print(f"Wrote Studio sync script to {LUAU_PATH}")


if __name__ == "__main__":
    print(f"Total entries to localize: {len(ENTRIES)}")
    write_csv()
    write_sync_script()
