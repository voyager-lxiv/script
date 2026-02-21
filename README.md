voyager-lxiv@localhost:~/Music> ~/bin/find_unique-id.sh
```
Duplicate ID group:
-------------------
1. 6. [29147212-6027-4613-ab98-56b1e06c6e2e] Panchhi Bole.flac 32M ./export/tag/flac/2015/Baahubali - The Beginning
2. 6. [29147212-6027-4613-ab98-56b1e06c6e2e] Panchhi Bole.m4a 11M ./export/tag/m4a/2015/Baahubali - The Beginning

Duplicate ID group:
-------------------
1. 1. [55ff13c0-0396-466f-8ea2-da3b6f640e48] more than words.m4a 12M ./export/tag/m4a/2023/more than words
2. 1. [55ff13c0-0396-466f-8ea2-da3b6f640e48] more than words.m4a 12M ./test

Duplicate ID group:
-------------------
1. 1. [671303f0-f811-4d4d-9ecf-bb20c95bb961] Jab Koi Baat Bigad Jaye.flac 51M ./export/tag/flac/1990/Jurm
2. 1. [671303f0-f811-4d4d-9ecf-bb20c95bb961] Jab Koi Baat Bigad Jaye.m4a 19M ./export/tag/m4a/1990/Jurm

Duplicate ID group:
-------------------
1. 2. [ece5d5ef-bf2c-4568-81c6-69ae62fb08b5] Dildaara (Stand by Me).flac 30M ./export/tag/flac/2011/Ra.One
2. 2. [ece5d5ef-bf2c-4568-81c6-69ae62fb08b5] Dildaara (Stand by Me).m4a 9.8M ./export/tag/m4a/2011/Ra.One

Duplicate ID group:
-------------------
1. 2. [edb39144-3f0e-40d6-9f7a-74fec4d8b16c] Saathiyaa.flac 35M ./export/tag/flac/2011/Singham
2. 2. [edb39144-3f0e-40d6-9f7a-74fec4d8b16c] Saathiyaa.m4a 13M ./export/tag/m4a/2011/Singham
```

voyager-lxiv@localhost:~/Music> ~/bin/find_unique-id.sh --delete
```
Duplicate ID group:
-------------------
1. 6. [29147212-6027-4613-ab98-56b1e06c6e2e] Panchhi Bole.flac 32M ./export/tag/flac/2015/Baahubali - The Beginning
2. 6. [29147212-6027-4613-ab98-56b1e06c6e2e] Panchhi Bole.m4a 11M ./export/tag/m4a/2015/Baahubali - The Beginning

[1-2 delete | a=delete all | s=skip | q=quit]: 
```

voyager-lxiv@localhost:~/Music> ~/bin/find_unique-id.sh --exclude -f flac --delete
```
Duplicate ID group:
-------------------
1. 1. [55ff13c0-0396-466f-8ea2-da3b6f640e48] more than words.m4a 12M ./export/tag/m4a/2023/more than words
2. 1. [55ff13c0-0396-466f-8ea2-da3b6f640e48] more than words.m4a 12M ./test

[1-2 delete | a=delete all | s=skip | q=quit]: 
```
