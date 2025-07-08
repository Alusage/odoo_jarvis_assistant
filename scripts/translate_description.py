#!/usr/bin/env python3
"""
Script pour traduire dynamiquement les descriptions GitHub des dépôts OCA
Utilise plusieurs services de traduction selon leur disponibilité
"""

import sys
import json
import requests
import urllib.parse
import time
import hashlib
from typing import Optional, Dict


class TranslationService:
    """Classe de base pour les services de traduction"""

    def translate(
        self, text: str, target_lang: str, source_lang: str = "en"
    ) -> Optional[str]:
        raise NotImplementedError


class GoogleTranslateService(TranslationService):
    """Service de traduction utilisant l'API Google Translate gratuite"""

    def __init__(self):
        self.base_url = "https://translate.googleapis.com/translate_a/single"
        self.session = requests.Session()
        self.session.headers.update(
            {
                "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
            }
        )

    def translate(
        self, text: str, target_lang: str, source_lang: str = "en"
    ) -> Optional[str]:
        """Traduit un texte en utilisant Google Translate"""
        if not text or not text.strip():
            return ""

        try:
            # Paramètres pour l'API Google Translate
            params = {
                "client": "gtx",
                "sl": source_lang,
                "tl": target_lang,
                "dt": "t",
                "q": text,
            }

            response = self.session.get(self.base_url, params=params, timeout=10)
            response.raise_for_status()

            # Parser la réponse JSON de Google Translate
            result = response.json()
            if result and len(result) > 0 and len(result[0]) > 0:
                translated_text = "".join([item[0] for item in result[0] if item[0]])
                return translated_text.strip()

        except Exception as e:
            print(f"❌ Erreur Google Translate: {e}", file=sys.stderr)

        return None


class LibreTranslateService(TranslationService):
    """Service de traduction utilisant LibreTranslate (gratuit et open source)"""

    def __init__(self):
        # Instances publiques de LibreTranslate
        self.instances = [
            "https://libretranslate.de",
            "https://translate.argosopentech.com",
            "https://translate.terraprint.co",
        ]
        self.session = requests.Session()

    def translate(
        self, text: str, target_lang: str, source_lang: str = "en"
    ) -> Optional[str]:
        """Traduit un texte en utilisant LibreTranslate"""
        if not text or not text.strip():
            return ""

        for instance in self.instances:
            try:
                response = self.session.post(
                    f"{instance}/translate",
                    json={"q": text, "source": source_lang, "target": target_lang},
                    timeout=10,
                )

                if response.status_code == 200:
                    result = response.json()
                    if "translatedText" in result:
                        return result["translatedText"].strip()

            except Exception as e:
                print(f"❌ Erreur LibreTranslate ({instance}): {e}", file=sys.stderr)
                continue

        return None


class MyMemoryService(TranslationService):
    """Service de traduction utilisant MyMemory (gratuit)"""

    def __init__(self):
        self.base_url = "https://api.mymemory.translated.net/get"
        self.session = requests.Session()

    def translate(
        self, text: str, target_lang: str, source_lang: str = "en"
    ) -> Optional[str]:
        """Traduit un texte en utilisant MyMemory"""
        if not text or not text.strip():
            return ""

        try:
            params = {"q": text, "langpair": f"{source_lang}|{target_lang}"}

            response = self.session.get(self.base_url, params=params, timeout=10)
            response.raise_for_status()

            result = response.json()
            if result.get("responseStatus") == 200:
                translated_text = result.get("responseData", {}).get(
                    "translatedText", ""
                )
                if (
                    translated_text
                    and translated_text.upper() != "PLEASE SELECT A VALID LANGUAGE PAIR"
                ):
                    return translated_text.strip()

        except Exception as e:
            print(f"❌ Erreur MyMemory: {e}", file=sys.stderr)

        return None


class TranslationManager:
    """Gestionnaire des services de traduction avec fallback"""

    def __init__(self):
        self.services = [
            GoogleTranslateService(),
            LibreTranslateService(),
            MyMemoryService(),
        ]
        self.cache = {}  # Cache simple en mémoire (session uniquement)

    def _get_cache_key(self, text: str, target_lang: str, source_lang: str) -> str:
        """Génère une clé de cache pour éviter les traductions redondantes"""
        content = f"{text}|{source_lang}|{target_lang}"
        return hashlib.md5(content.encode()).hexdigest()

    def translate(self, text: str, target_lang: str, source_lang: str = "en") -> str:
        """Traduit un texte en essayant les services disponibles"""
        if not text or not text.strip():
            return ""

        # Si la langue source et cible sont identiques, pas besoin de traduire
        if source_lang == target_lang:
            return text

        # Vérifier le cache en mémoire (session uniquement)
        cache_key = self._get_cache_key(text, target_lang, source_lang)
        if cache_key in self.cache:
            return self.cache[cache_key]

        # Essayer les services de traduction un par un
        for i, service in enumerate(self.services):
            try:
                print(
                    f"🔄 Tentative de traduction avec le service {i+1}...",
                    file=sys.stderr,
                )
                translated = service.translate(text, target_lang, source_lang)

                if translated:
                    print(
                        f"✅ Traduction réussie avec le service {i+1}", file=sys.stderr
                    )
                    # Mettre en cache en mémoire uniquement
                    self.cache[cache_key] = translated
                    return translated

            except Exception as e:
                print(f"❌ Échec du service {i+1}: {e}", file=sys.stderr)
                continue

            # Petite pause entre les tentatives
            if i < len(self.services) - 1:
                time.sleep(0.5)

        # Aucun service n'a fonctionné, retourner le texte original
        print(f"⚠️  Impossible de traduire, retour du texte original", file=sys.stderr)
        return text


def get_github_description(repo_name: str) -> Optional[str]:
    """Récupère la description d'un dépôt GitHub OCA"""

    try:
        url = f"https://api.github.com/repos/OCA/{repo_name}"
        response = requests.get(url, timeout=10)
        response.raise_for_status()

        repo_data = response.json()
        description = repo_data.get("description", "").strip()

        # Filtrer les descriptions vides ou génériques
        if description and description.lower() not in [
            "",
            "null",
            "none",
            "odoo addons",
        ]:
            return description

    except Exception as e:
        print(
            f"❌ Erreur lors de la récupération de la description GitHub pour {repo_name}: {e}",
            file=sys.stderr,
        )

    return None


def main():
    """Fonction principale"""
    if len(sys.argv) < 3:
        print(
            "Usage: python3 translate_description.py <repo_name> <target_lang> [source_lang]",
            file=sys.stderr,
        )
        print(
            "Exemple: python3 translate_description.py account-analytic fr en",
            file=sys.stderr,
        )
        sys.exit(1)

    repo_name = sys.argv[1]
    target_lang = sys.argv[2]
    source_lang = sys.argv[3] if len(sys.argv) > 3 else "en"

    # Récupérer la description GitHub
    print(
        f"🔍 Récupération de la description GitHub pour {repo_name}...", file=sys.stderr
    )
    github_description = get_github_description(repo_name)

    if not github_description:
        print(f"⚠️  Aucune description GitHub trouvée pour {repo_name}", file=sys.stderr)
        # Retourner une description par défaut
        if target_lang == "fr":
            print("Module OCA")
        else:
            print("OCA module")
        sys.exit(0)

    print(f'📝 Description GitHub trouvée: "{github_description}"', file=sys.stderr)

    # Traduire la description
    translator = TranslationManager()
    translated_description = translator.translate(
        github_description, target_lang, source_lang
    )

    print(
        f'🌍 Description traduite ({target_lang}): "{translated_description}"',
        file=sys.stderr,
    )

    # Sortir uniquement la traduction (sans les messages de debug) sur stdout
    print(translated_description)


if __name__ == "__main__":
    main()
