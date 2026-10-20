#!/usr/bin/env python3
"""Türkçe Swift string literal'leri için iki dilde anahtar kapsamını denetler."""
import itertools
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
TURKISH = re.compile(r"[çğıöşüÇĞİÖŞÜ]")
# Türkçe karakter içermeyen ("Tara", "Geri Al") ama yerelleştirilen API'lere giden literal'ler de denetlenir.
LOCALIZED_CALL = re.compile(r'(?:\b(?:Text|TextField|Button|Label|Toggle|Picker|ProgressView|Section|LabeledContent)\(|'
                            r'\.(?:help|navigationTitle|confirmationDialog|accessibilityLabel)\(|'
                            r'\bString\(localized:)\s*$')
BRAND = {'MacErase'}


def literals(source):
    """Yorumları atlar; iç içe enterpolasyonları ve string'leri ayrı okur."""
    found = []

    def comment(i):
        if source.startswith('//', i):
            end = source.find('\n', i)
            return len(source) if end < 0 else end
        depth, i = 1, i + 2
        while i < len(source) and depth:
            if source.startswith('/*', i):
                depth += 1
                i += 2
            elif source.startswith('*/', i):
                depth -= 1
                i += 2
            else:
                i += 1
        return i

    def string(i):
        start = i
        while source[i:i + 1] == '#':
            i += 1
        hashes = source[start:i]
        quote = '"""' if source.startswith('"""', i) else '"'
        i += len(quote)
        body, expressions = [], []
        escape = '\\' + hashes
        while i < len(source):
            if source.startswith(quote + hashes, i):
                end = i + len(quote + hashes)
                found.append((start, end, ''.join(body), expressions))
                return end
            if source.startswith(escape + '(', i):
                expr_start = i + len(escape) + 1
                i, depth = expr_start, 1
                while i < len(source) and depth:
                    if source.startswith(('//', '/*'), i):
                        i = comment(i)
                    elif re.match(r'(#*)"', source[i:i + 32]):
                        i = string(i)
                    else:
                        if source[i] == '(':
                            depth += 1
                        elif source[i] == ')':
                            depth -= 1
                        i += 1
                expressions.append(source[expr_start:i - 1])
                body.append('\x00')
            elif source.startswith(escape, i):
                i += len(escape)
                c = source[i:i + 1]
                if c == 'u' and source[i + 1:i + 2] == '{':
                    end = source.index('}', i + 2)
                    body.append(chr(int(source[i + 2:end], 16)))
                    i = end + 1
                else:
                    body.append({'n': '\n', 'r': '\r', 't': '\t', '0': '\0'}.get(c, c))
                    i += 1
            else:
                body.append(source[i])
                i += 1
        raise ValueError(f'Kapanmamış string: {start}')

    i = 0
    while i < len(source):
        if source.startswith(('//', '/*'), i):
            i = comment(i)
        elif re.match(r'(#*)"', source[i:i + 32]):
            i = string(i)
        else:
            i += 1
    return sorted(found)


def placeholder(expression):
    """Bilinen sayısal ifadeler dışındakiler String olarak tahmin edilir."""
    if re.search(r'\bInt(?:64)?\(|\.count\b|\.percent\b|\.restored\b', expression):
        return '%lld', False
    if expression.strip() in {'failed', 'restored', 'locked'} or '$0 /' in expression or '$0 %' in expression:
        return '%lld', False
    if re.search(r'Fmt\.|\.name\b|\.label\b|\.version\b', expression):
        return '%@', False
    return '%@', True


def key_for(body, expressions):
    if not expressions:
        return body, False
    parts = body.replace('%', '%%').split('\x00')
    key, uncertain = parts[0], False
    for expression, part in zip(expressions, parts[1:]):
        token, guessed = placeholder(expression)
        key += token + part
        uncertain |= guessed
    return key, uncertain


def read_strings(path):
    source = path.read_text()
    pair = re.compile(r'("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*")\s*;')
    trivia = re.compile(r'\s+|/\*.*?\*/|//[^\n]*', re.S)
    entries, offset = {}, 0
    while offset < len(source):
        skipped = trivia.match(source, offset)
        if skipped:
            offset = skipped.end()
            continue
        match = pair.match(source, offset)
        if not match:
            raise ValueError(f'{path}: geçersiz .strings biçimi: {offset}')
        key, value = (json.loads(s) for s in match.groups())
        if key in entries:
            raise ValueError(f'{path}: yinelenen anahtar: {key}')
        entries[key] = value
        offset = match.end()
    return entries


def main():
    catalogs = {lang: read_strings(ROOT / 'Resources' / f'{lang}.lproj' / 'Localizable.strings')
                for lang in ('tr', 'en')}
    errors, warnings, checked = [], [], set()
    for path in sorted((ROOT / 'Sources').rglob('*.swift')):
        source = path.read_text()
        for start, _, body, expressions in literals(source):
            in_call = LOCALIZED_CALL.search(source[max(0, start - 64):start])
            letters = re.search(r'[A-Za-z]', body.replace('\x00', ''))
            if not TURKISH.search(body) and not (in_call and letters and body not in BRAND):
                continue
            key, uncertain = key_for(body, expressions)
            location = f'{path.relative_to(ROOT)}:{source.count(chr(10), 0, start) + 1}'
            checked.add(key)
            candidates = [key]
            if uncertain:
                warnings.append(f'uyarı: {location}: enterpolasyon türü tahmini: {key}')
                parts = body.replace('%', '%%').split('\x00')
                # Belirsiz türde yanlış eksik bildirmemek için iki biçimi de dene.
                candidates = [parts[0] + ''.join(t + p for t, p in zip(tokens, parts[1:]))
                              for tokens in itertools.product(('%lld', '%@'), repeat=len(expressions))]
            checked.update(c for c in candidates if c in catalogs['tr'])
            for lang, catalog in catalogs.items():
                if not any(candidate in catalog for candidate in candidates):
                    errors.append(f'EKSİK [{lang}]: {location}: {key}')
    for key in sorted(set(catalogs['tr']) - checked):
        warnings.append(f'uyarı: kodda kullanılmayan anahtar: {key}')
    for lang, catalog in catalogs.items():
        for key, value in catalog.items():
            if lang == 'tr' and key != value:
                errors.append(f'Türkçe anahtar/değer farklı: {key}')
            if key not in catalogs['en' if lang == 'tr' else 'tr']:
                errors.append(f'Diller arasında eksik anahtar [{lang}]: {key}')
    for line in warnings + errors:
        print(line)
    print(f'check_l10n: {len(checked)} anahtar denetlendi; '
          f'tr={len(catalogs["tr"])}, en={len(catalogs["en"])}; '
          f'{len(errors)} hata, {len(warnings)} uyarı.')
    return 1 if errors else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError) as error:
        print(f'check_l10n: HATA: {error}', file=sys.stderr)
        sys.exit(1)
