function normalize(value) {
  return String(value || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
}

function tokens(value) {
  return normalize(value).split(/[^\p{L}\p{N}+#]+/u).filter(Boolean)
}

function stem(token) {
  if (token.length > 4 && token.endsWith("ies")) return `${token.slice(0, -3)}y`
  if (token.length > 4 && token.endsWith("es")) return token.slice(0, -2)
  if (token.length > 3 && token.endsWith("s")) return token.slice(0, -1)
  return token
}

function editDistanceWithin(left, right, limit) {
  if (Math.abs(left.length - right.length) > limit) return false

  let previous = Array.from({ length: right.length + 1 }, (_, index) => index)

  for (let leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    const current = [leftIndex]
    let rowMinimum = current[0]

    for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      const substitutionCost = left[leftIndex - 1] === right[rightIndex - 1] ? 0 : 1
      const distance = Math.min(
        previous[rightIndex] + 1,
        current[rightIndex - 1] + 1,
        previous[rightIndex - 1] + substitutionCost
      )
      current.push(distance)
      rowMinimum = Math.min(rowMinimum, distance)
    }

    if (rowMinimum > limit) return false
    previous = current
  }

  return previous[right.length] <= limit
}

function tokenMatches(queryToken, candidateToken, allowTypos) {
  if (candidateToken.includes(queryToken)) return true

  const queryStem = stem(queryToken)
  const candidateStem = stem(candidateToken)
  if (candidateStem === queryStem) return true

  const typoAllowance = queryStem.length >= 4 ? 1 : 0
  return allowTypos && typoAllowance > 0 && editDistanceWithin(queryStem, candidateStem, typoAllowance)
}

export function emojiSearchMatches(searchText, query, { allowTypos = true } = {}) {
  const queryTokens = tokens(query)
  if (queryTokens.length === 0) return true

  const candidateTokens = tokens(searchText)
  return queryTokens.every((queryToken) =>
    candidateTokens.some((candidateToken) => tokenMatches(queryToken, candidateToken, allowTypos))
  )
}
