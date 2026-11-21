# arabic-video-tools

[العربي](#العربي) | [English](#english)

---

## العربي

### 1. شو هاي الأدوات
أدوات صغيرة بـ PowerShell لويندوز: بتحوّل كلام الفيديو لنص، وبتحرق الترجمة على الفيديو، وبتقص السكوت، وبتجهّز صور ونصوص مرتبة عشان تشتغل عليها مع أي مساعد ذكاء اصطناعي. والترجمة العربية بتطلع صح: الحروف متصلة، والسطر من اليمين لليسار.
- كل إشي بيشتغل على جهازك، بدون إنترنت وبدون اشتراك، ومجاني.
- كل أداة بتعمل شغلة وحدة، وبتشتغلهم كلهم من قائمة مرقّمة وحدة.
- كل أداة بتشتغل أول تجربة جافة: بتطبع شو رح تعمل وما بتكتب إشي. بس مع `-Run` بتشتغل فعلاً.
- ما بتحذف ولا بتكتب فوق أي ملف، والفيديو الأصلي ما بيتغيّر.

هاي النسخة الكاملة (v1.0): عشر أدوات بقائمة وحدة.

### 2. فيديو قبل وبعد
![قبل وبعد: نفس الفيديو بدون ترجمة، ومعه ترجمة إنجليزية بالنص وعربية تحت، محروقة على الفيديو](docs/before-after.png)

### 3. التنزيل وفتح PowerShell
1. بصفحة الريبو على GitHub: اكبس على زر Code، وبعدين Download ZIP.
2. فك الضغط بمجلد بتختاره. هاد المجلد هو «مجلد الريبو»، وفيه `video-tools.root` و `tools`.
3. افتح PowerShell، وادخل على المجلد قبل أي أمر بهالصفحة:
   ```
   cd "<مجلد الريبو>"
   ```
   كل الأوامر الجاية بتشتغل من هون.

### 4. شو لازم تركّب
1. Windows 10 أو 11، وفيه Windows PowerShell 5.1 (موجود أصلاً).
2. ffmpeg نسخة full، 9 أو أحدث، لأنه لازم يكون فيه فلتر whisper وفلتر libass:
   ```
   winget install Gyan.FFmpeg
   ```
   تأكد إنه الفلترين موجودين: `ffmpeg -filters` لازم يبيّن فيه `whisper` و `subtitles`.
3. موديل whisper، ملف `ggml-large-v3-turbo-q5_0.bin` (حوالي 547 MB)، من صفحة `ggerganov/whisper.cpp` على Hugging Face:
   https://huggingface.co/ggerganov/whisper.cpp/tree/main
   الملف بيتحط بـ `videos\models\` (شوف التجهيز).

### 5. التجهيز (المجلدات وملف الإعداد)
من مجلد الريبو (المجلد اللي فيه `video-tools.root`)، اعمل المجلدات بأمر واحد:
```
New-Item -ItemType Directory videos\inbox, videos\work, videos\out, videos\done, videos\models
```
- `videos\inbox`: هون بتحط الفيديوهات الجديدة.
- `videos\work`: الصوت والنص (wav و srt).
- `videos\out`: النتائج (القوائم، وملف التسليم، والفيديو مع الترجمة).
- `videos\done`: الفيديوهات اللي خلصت.
- `videos\models`: موديل whisper.

ملف الإعداد اختياري. إذا ما عملته، كل إشي بياخد القيمة الافتراضية، و ffmpeg بيندوّر عليه بالـ PATH.
إذا بدك تغيّر إشي: انسخ `tools\video-config.example.psd1` لـ `tools\video-config.local.psd1` بنفس المجلد، وغيّر بس السطر اللي بدك إياه. مثلاً `FfmpegBin` لمجلد ffmpeg عندك. الملف المحلي ما بيدخل git، وبينقرأ كبيانات بس، يعني ما بيشغّل كود.

### 6. أول تشغيل (القائمة)
أول مرة، بدون `-Run`. هيك القائمة بتسأل نفس الأسئلة، بس بتطبع الأمر وما بتشغّل إشي:
```
powershell -ExecutionPolicy Bypass -File tools\video-menu.ps1
```
لما تتأكد إنه كل إشي مزبوط، نفس الأمر مع `-Run`:
```
powershell -ExecutionPolicy Bypass -File tools\video-menu.ps1 -Run
```
بأول سطر بالقائمة بتشوف `MODE DRY` أو `MODE RUN`.

### 7. الأيقونة
على سطح المكتب: كبسة يمين، وبعدين New > Shortcut، وبالهدف حط (غيّر `<مجلد الريبو>` لمكانه عندك):
```
powershell.exe -ExecutionPolicy Bypass -File "<مجلد الريبو>\tools\video-menu.ps1" -Run
```

### 8. الأدوات واحدة واحدة
بالقائمة:
- `1` الخط الكامل على inbox (`video-run`): بيشغّل الخمس مراحل ورا بعض، وبيوقف إذا مرحلة فشلت.
- `2` صور من الفيديو (`video-frames`): صورة لكل مقطع كلام بالـ srt، مأخوذة بالنص بين بداية الجملة واللي بعدها، عشان الشاشة تطابق الكلام. وبيكتب `notes.md` فيه الجملة تحت كل صورة، ومكان فاضي لملاحظتك وسؤالك. كله بمجلد جديد `out\frames-...`.
- `3` لحظات بتختارها (`video-moments`): أول مرة بيعمل ملف `videos\moments\<اسم الفيديو>.txt`. بتكتب فيه سطر لكل لحظة بهالشكل: `الوقت | طلبك`، مثلاً `01:10 | اشرحلي شو هاد`. وبعدين بياخد صورة عند كل وقت، وبيكتب `moments.md` فيه الصور والطلبات، بمجلد جديد `out\moments-...`. ما بينفّذ ولا طلب، بس بيجهّزه.
- `4` zip للرفع (`video-upload`): zip واحد للفيديو فيه ملف التسليم، وآخر صور، وآخر لحظات، و `card-format.md`. بترفعه لمساعد ذكاء اصطناعي مرة وحدة، بدل ما تدوّر بالمجلدات. بينحط بمجلد `upload`.
- `5` حفظ بطاقة (`video-card-save`): «البطاقة» ملف `.md` قصير عن فيديو واحد (الأفكار والحكم)، بيكتبه المساعد بشكل `card-format.md` وإنت بتنزّله. هاد الخيار بيفحص البطاقة بـ Downloads، وإذا سليمة بينقلها لمجلد `library`. البطاقة اللي فيها مشكلة ما بتنتقل، وبيطبع كل المشاكل مرة وحدة.
- `6` جمع البطاقات (`video-card-pack`): كل البطاقات، أو بطاقات بالاسم، أو بموضوع، بملف واحد `out\library-....md`، عشان المساعد يربط الأفكار بين الفيديوهات.
- `7` قص السكوت (`video-cut`): بيشيل السكتات من فيديو واحد بـ ffmpeg بس، بدون ذكاء اصطناعي، وبيخلي 0.15 ثانية على طرفي كل سكتة عشان الكلمات ما تنقص. بيكتب الفيديو المقصوص، و srt جديد بأوقات الفيديو المقصوص، و cut.csv، بمجلد جديد `out\cut-...`، والأصلي ما بيتغيّر.
- `8` حرق الترجمة (`video-subs`): بيحرق الـ srt على فيديو واحد، وبيكتب الفيديو الجديد بمجلد جديد `out\subs-...`. وإذا خيار 7 موجود، بيسأل إذا بدك تحرق على آخر فيديو مقصوص.
- `9` بينقل فيديو خلص من inbox لـ done.
- `10` فيديو ملخص (`video-summary`): من بطاقة، بيعمل فيديو عمودي قصير 1080×1920: العنوان، ولحد 3 أفكار، والحكم، 3 ثواني لكل مشهد. اختياري، وبده Hyperframes (شوف القسم 10).
- `0` خروج.

الخمس مراحل (`video-run` بيشغّلهم، وكل وحدة بتشتغل لحالها كمان):
1. `video-list`: بيقرأ أسماء الفيديوهات بـ inbox.
2. `video-length`: مدة كل فيديو، وإذا فيه صوت (أطول من 15 دقيقة بيطلع `too_long`).
3. `video-audio`: بيطلّع الصوت لملف wav.
4. `video-text`: بيحوّل الصوت لنص srt بـ whisper (اللغة بتنعرف لحالها).
5. `video-handoff`: ملف نص واحد مرتب لكل الفيديوهات، جملة بكل سطر مع الوقت. فيك تلصقه بأي مساعد ذكاء اصطناعي عشان يصحّح ويلخّص.

`video-subs` لحالها:
```
powershell -ExecutionPolicy Bypass -File tools\video-subs.ps1 -Name video-01.mp4 -Lang ar -Position bottom -Run
```
- `-Lang ar` بيحرق `<اسم الفيديو>.ar.srt` من `videos\work`، وبيخلي كل سطر من اليمين لليسار. إذا هالملف مش موجود، بيستعمل الـ srt العادي وبيطبع تحذير أصفر.
- `-Position` بيقبل bottom أو middle أو top، و `-FontSize` و `-MarginV` و `-MaxWords` بيتحكموا بالحجم والمكان وعدد الكلمات بكل قطعة.

ترجمة عربية لفيديو بلغة تانية:
1. شغّل الخط الكامل (خيار 1)، فبيطلع `videos\work\<اسم الفيديو>.srt`.
2. خلّي أي مساعد ذكاء اصطناعي يترجم هالملف للعربي، بنفس الأرقام والأوقات، وأسماء البرامج تضل بالإنجليزي.
3. احفظ الترجمة جنبه بـ `videos\work` باسم `<اسم الفيديو>.ar.srt`، مثلاً `video-01.mp4.ar.srt`.
4. احرقها بخيار 8، وجاوب y على `Arabic captions (-Lang ar)?`.

وإذا الفيديو أصلاً بالعربي، `-Lang ar` لحاله بيكفي: الـ srt العادي عربي أصلاً.

### 9. الشغل مع مساعد ذكاء اصطناعي (اختياري)
الأدوات نفسها ما فيها ذكاء اصطناعي ولا بتحكي مع الإنترنت (whisper بيشتغل على جهازك). هي بس بتجهّز ملفات مرتبة بترفعها أو بتلصقها لأي مساعد بتختاره. طريقة وحدة للشغل:
1. خيار `1`: النص من الفيديو.
2. خيار `2` أو `3`: الصور، كل الفيديو أو لحظات بتختارها.
3. خيار `4`: zip واحد، بترفعه للمساعد وبتطلب منه دليل للمبتدئ، أو شرح للحظات اللي اخترتها.
4. اطلب من المساعد بطاقة للفيديو بشكل `card-format.md`، ونزّلها.
5. خيار `5`: احفظ البطاقة بالمكتبة.
6. خيار `6`: اجمع البطاقات، وارفع الملف، واطلب منه يربط الأفكار بين الفيديوهات.
7. خيار `10` (اختياري): فيديو ملخص قصير من بطاقة.

الملفات اللي بتطلع (`notes.md` و `moments.md` وملف المكتبة) فيها بأولها سطور قصيرة بالإنجليزي للمساعد، بتحكيله شو المطلوب.

### 10. فيديو الملخص و Hyperframes (اختياري)
خيار `10` بس بده [Hyperframes](https://www.npmjs.com/package/hyperframes)، والخيارات الباقية ما بتحتاجه.
1. ركّب Node.js.
2. اعمل مجلد لـ Hyperframes برا الريبو، مثلاً `C:\hyperframes`، وركّبه فيه (انجرّبت الأدوات مع النسخة 0.9.52):
   ```
   cd C:\hyperframes
   npm install hyperframes@0.9.52 --ignore-scripts --no-fund --no-audit
   ```
3. Hyperframes بيرسم الفيديو بـ Chrome، ولازم Chrome يكون بمجلد `hf-cache` جوا نفس المجلد. الأداة ما بتنزّل ولا إشي، فإذا مش موجود بتوقف بـ STOP. شوف تعليمات Hyperframes لأول تشغيل، مع `HYPERFRAMES_CACHE_DIR` على `C:\hyperframes\hf-cache`.
4. بملف الإعداد المحلي، حط `HyperframesDir = 'C:\hyperframes'`.

الأداة بتشغّل Hyperframes بس لوقت الرسم، ومعه إعدادات بتطفي الإحصائيات (telemetry) وفحص التحديثات. وما بتغيّر إشي بالجهاز، وما بتشغّل npm ولا npx.

### 11. الخصوصية
- كل الشغل على جهازك. ما في إنترنت، ولا حساب، ولا إرسال لأي مكان.
- الإنترنت بيلزم بس لتركيب ffmpeg وتنزيل الموديل مرة وحدة (و Hyperframes إذا بدك خيار 10).
- إذا رفعت ملفات لمساعد ذكاء اصطناعي، هاد قرارك وبحسابك. الأدوات ما بترفع إشي لحالها.
- الفيديوهات والنصوص بتضل بمجلد `videos`، وهو مش داخل git.

### 12. مشاكل معروفة
- العربي بنافذة PowerShell بيبيّن مقلوب. هاد عرض بس، وبالفيديو وبالملفات صح.
- whisper أحياناً بيكتب الكلمات الإنجليزية التقنية غلط بالكلام العربي، فراجع النص قبل ما تحرقه.
- whisper ممكن يخترع نص بالسكوت أو بآخر الفيديو. ملف التسليم بيعلّم هالجمل بـ `[?]`، وما بيشيل إشي.
- فلتر whisper ما بيقبل حرف القرص (C:) بالمسار، فالموديل لازم يكون جوا مجلد `videos`.
- إذا ffmpeg جاي من الـ PATH، بيطلع تحذير أصفر. هاد طبيعي، بس تأكد إنه فيه whisper و libass، أو حط `FfmpegBin` بملف الإعداد.

### 13. الرخصة
MIT. شوف ملف [LICENSE](LICENSE).

---

## English

### 1. What it does
Small PowerShell tools for Windows: they turn the speech in a video into text, burn captions onto the video, remove silences, and prepare tidy frames and text to work on with any AI assistant. Arabic captions come out right: joined letters, and each line right to left.
- Everything runs on your machine: no internet, no account, free.
- Each tool does one job, and one numbered menu runs them all.
- Each tool starts as a dry run: it prints what it would do and writes nothing. Only with `-Run` does it really work.
- Nothing is ever deleted or overwritten, and the original video never changes.

This is the full version (v1.0): ten tools in one menu.

### 2. Before and after
![Before and after: the same video without captions, then with English captions in the middle and Arabic captions at the bottom, burned onto the video](docs/before-after.png)

### 3. Download and open PowerShell
1. On the repo page on GitHub: click the Code button, then Download ZIP.
2. Unzip it into a folder you choose. That folder is the "repo folder": it has `video-tools.root` and `tools`.
3. Open PowerShell and go into that folder before any command on this page:
   ```
   cd "<repo folder>"
   ```
   All the commands below run from there.

### 4. Requirements
1. Windows 10 or 11, with Windows PowerShell 5.1 (already there).
2. ffmpeg, a full build, version 9 or newer, because it needs the whisper filter and libass:
   ```
   winget install Gyan.FFmpeg
   ```
   Check both filters: `ffmpeg -filters` must list `whisper` and `subtitles`.
3. The whisper model `ggml-large-v3-turbo-q5_0.bin` (about 547 MB), from the `ggerganov/whisper.cpp` page on Hugging Face:
   https://huggingface.co/ggerganov/whisper.cpp/tree/main
   It goes in `videos\models\` (see Setup).

### 5. Setup
From the repo folder (the one with `video-tools.root`), make the folders with one command:
```
New-Item -ItemType Directory videos\inbox, videos\work, videos\out, videos\done, videos\models
```
- `videos\inbox`: put new videos here.
- `videos\work`: audio and text (wav and srt).
- `videos\out`: results (lists, the handoff file, the captioned video).
- `videos\done`: finished videos.
- `videos\models`: the whisper model.

The settings file is optional. Without it every value takes its default, and ffmpeg is looked for on PATH.
To change something: copy `tools\video-config.example.psd1` to `tools\video-config.local.psd1` in the same folder and set only the lines you need, for example `FfmpegBin` to your ffmpeg folder. The local file stays out of git and is read as data only, so it never runs code.

### 6. First run
The first time, without `-Run`. The menu asks the same questions but only prints the command:
```
powershell -ExecutionPolicy Bypass -File tools\video-menu.ps1
```
When all looks right, the same command with `-Run`:
```
powershell -ExecutionPolicy Bypass -File tools\video-menu.ps1 -Run
```
The first line of the menu shows `MODE DRY` or `MODE RUN`.

### 7. Desktop icon
On the desktop: right click, New > Shortcut, and as the target (change `<repo folder>` to where it is on your machine):
```
powershell.exe -ExecutionPolicy Bypass -File "<repo folder>\tools\video-menu.ps1" -Run
```

### 8. Tools
In the menu:
- `1` Full pipeline on inbox (`video-run`): runs the five stages in order and stops if one fails.
- `2` Frames for a video (`video-frames`): one frame for each block of speech in the srt, taken halfway between a sentence and the next one, so the screen matches the words. It also writes `notes.md` with the sentence under each frame and room for your note and question. All in a new `out\frames-...` folder.
- `3` Moments you pick (`video-moments`): the first time it makes `videos\moments\<video name>.txt`. You write one line per moment in it: `time | your request`, for example `01:10 | explain what this is`. Then it takes a frame at each time and writes `moments.md` with the frames and the requests, in a new `out\moments-...` folder. It never runs a request, it only prepares it.
- `4` Zip for upload (`video-upload`): one zip for one video with the handoff file, the newest frames, the newest moments and `card-format.md`. You upload it to an AI assistant once, instead of searching the folders. It goes in the `upload` folder.
- `5` Save a card (`video-card-save`): a "card" is a short `.md` file about one video (its ideas and a verdict), written by the assistant in the `card-format.md` shape and downloaded by you. This option checks the card in Downloads and, if it is fine, moves it to the `library` folder. A card with a problem is not moved, and every problem is printed at once.
- `6` Pack cards (`video-card-pack`): all cards, chosen cards or cards on one topic, in one file `out\library-....md`, so the assistant can link the ideas between videos.
- `7` Remove silences (`video-cut`): removes the silent parts of one video with ffmpeg only, no AI, and keeps 0.15 seconds at each side of a silence so words are not cut. Writes the cut video, a new srt with the times of the cut video, and cut.csv in a new `out\cut-...` folder. The original never changes.
- `8` Burn captions (`video-subs`): burns the srt onto one video and writes the new video in a new `out\subs-...` folder. When option 7 is there, it asks whether to burn onto the newest cut video.
- `9` Moves a finished video from inbox to done.
- `10` Summary video (`video-summary`): from a card, a short vertical 1080×1920 video: the title, up to 3 ideas and the verdict, 3 seconds each. Optional, and it needs Hyperframes (see section 10).
- `0` Exit.

The five stages (`video-run` runs them, and each one also runs alone):
1. `video-list`: reads the video names in inbox.
2. `video-length`: the length of each video and whether it has audio (over 15 minutes is `too_long`).
3. `video-audio`: pulls the audio into a wav file.
4. `video-text`: turns the audio into srt text with whisper (the language is found by itself).
5. `video-handoff`: one tidy text file for all the videos, one sentence per line with its time. You can paste it into any AI assistant to fix and sum it up.

`video-subs` alone:
```
powershell -ExecutionPolicy Bypass -File tools\video-subs.ps1 -Name video-01.mp4 -Lang ar -Position bottom -Run
```
- `-Lang ar` burns `<video name>.ar.srt` from `videos\work` and makes each line right to left. If that file is not there, it uses the normal srt and prints a yellow warning.
- `-Position` takes bottom, middle or top, and `-FontSize`, `-MarginV` and `-MaxWords` set the size, the place and the words in each piece.

Arabic captions for a video in another language:
1. Run the full pipeline (option 1), which writes `videos\work\<video name>.srt`.
2. Ask any AI assistant to translate that file to Arabic, with the same numbers and times, and program names kept in English.
3. Save the translation next to it in `videos\work` as `<video name>.ar.srt`, for example `video-01.mp4.ar.srt`.
4. Burn it with option 8, and answer y to `Arabic captions (-Lang ar)?`.

If the video is already in Arabic, `-Lang ar` alone is enough: the normal srt is already Arabic.

### 9. Working with an AI assistant (optional)
The tools themselves have no AI and never talk to the internet (whisper runs on your machine). They only prepare tidy files that you upload or paste into any assistant you choose. One way to work:
1. Option `1`: the text from the video.
2. Option `2` or `3`: frames, for the whole video or for moments you pick.
3. Option `4`: one zip, which you upload to the assistant with a request for a beginner guide, or an explanation of the moments you picked.
4. Ask the assistant for a card for the video in the `card-format.md` shape, and download it.
5. Option `5`: save the card in the library.
6. Option `6`: pack the cards, upload the file and ask it to link the ideas between videos.
7. Option `10` (optional): a short summary video from a card.

The files they write (`notes.md`, `moments.md` and the library file) start with a few short lines in English for the assistant that say what is wanted.

### 10. Summary video and Hyperframes (optional)
Only option `10` needs [Hyperframes](https://www.npmjs.com/package/hyperframes); the other options do not.
1. Install Node.js.
2. Make a folder for Hyperframes outside the repo, for example `C:\hyperframes`, and install it there (the tools were tested with version 0.9.52):
   ```
   cd C:\hyperframes
   npm install hyperframes@0.9.52 --ignore-scripts --no-fund --no-audit
   ```
3. Hyperframes renders with Chrome, and Chrome must be in the `hf-cache` folder inside that same folder. The tool downloads nothing, so without it you get a STOP. See the Hyperframes instructions for the first run, with `HYPERFRAMES_CACHE_DIR` set to `C:\hyperframes\hf-cache`.
4. In the local settings file, set `HyperframesDir = 'C:\hyperframes'`.

The tool runs Hyperframes only for the render, with settings that turn off telemetry and the update check. It changes nothing on the machine and never runs npm or npx.

### 11. Privacy
- All the work happens on your machine. No internet, no account, nothing is sent anywhere.
- The internet is needed only once, to install ffmpeg and download the model (and Hyperframes if you want option 10).
- If you upload files to an AI assistant, that is your choice and your account. The tools upload nothing by themselves.
- Videos and text stay in the `videos` folder, which is not in git.

### 12. Known issues
- Arabic in the PowerShell window shows reversed. That is the display only: the video and the files are right.
- whisper sometimes misspells English technical words in Arabic speech, so check the text before you burn it.
- whisper can invent text in silence or at the end of a video. The handoff file marks those lines with `[?]` and removes nothing.
- The whisper filter does not accept a drive letter (C:) in a path, so the model must be inside the `videos` folder.
- When ffmpeg comes from PATH you get a yellow warning. That is normal, but check it has whisper and libass, or set `FfmpegBin` in the settings file.

### 13. License
MIT. See [LICENSE](LICENSE).
