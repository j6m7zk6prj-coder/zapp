using System.Globalization;
using System.Text;

namespace ZappTV.Core;

public static class TextUtil
{
    /// <summary>Hash FNV-1a stable d'une exécution à l'autre.</summary>
    public static ulong StableHash(string value)
    {
        unchecked
        {
            ulong hash = 14695981039346656037;
            foreach (var b in Encoding.UTF8.GetBytes(value))
            {
                hash ^= b;
                hash *= 1099511628211;
            }
            return hash;
        }
    }

    /// <summary>Nom sans préfixe de pays du type « FR | ».</summary>
    public static string DisplayName(string name)
    {
        var index = name.LastIndexOf('|');
        if (index >= 0)
        {
            var rest = name[(index + 1)..].Trim();
            if (rest.Length > 0) return rest;
        }
        return name;
    }

    /// <summary>Deux premières initiales, quand il n'y a pas de logo.</summary>
    public static string Initials(string value)
    {
        var letters = value
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Where(w => char.IsLetterOrDigit(w[0]))
            .Take(2)
            .Select(w => char.ToUpper(w[0], CultureInfo.CurrentCulture));
        var result = string.Concat(letters);
        return result.Length == 0 ? "TV" : result;
    }

    public static bool ContainsLoose(string text, string term) =>
        CultureInfo.InvariantCulture.CompareInfo.IndexOf(
            text, term, CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace) >= 0;
}
