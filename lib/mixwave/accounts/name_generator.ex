defmodule Mixwave.Accounts.NameGenerator do
  @moduledoc """
  Generates anonymous-user display names in the form
  `<funny-javanese-noun>-<funny-javanese-adjective>-<NN>`, e.g.
  `tempe-gendheng-42`, `bakso-mendhem-17`, `monyet-ngantuk-08`.

  Nouns come first because the noun-then-adjective order reads
  naturally in Javanese / Indonesian — like a vendor's stall name
  ("Tempe gendheng!") rather than the English adj-then-noun word
  order. Adjectives are playful / mildly absurd descriptors:
  drunk, dazed, slovenly, dorky, sleepy, naughty. Nouns are
  Javanese food, animals, and body parts that read as funny
  whether you speak Javanese or not.

  30 adjectives × 30 nouns × 100 numbers = 90 000 unique names.
  Two-digit suffix lets the same adjective+noun pair map to many
  users without collision in practice; if it does collide on
  insert, the caller retries.

  """

  @adjectives ~w(
    gendheng edan kemproh cubluk cengeng culun mendhem klimis
    kemayu kemlinthi mblenger bantet kuru lemu ndlahom ndlosor
    ndableg kemladhean bedhes cilik gembleng alon nakal bandel
    slengeran lelet lemes ngantuk keseseg kringeten
  )

  @nouns ~w(
    tempe tahu bakso cendol klepon getuk krupuk peyek bakwan
    lemper sambal jagung timun terong jengkol pisang udel
    jenggot bekicot yuyu lutung monyet celeng kebo belut kodok
    tikus cacing kambing ayam
  )

  @doc """
  Returns a random `<noun>-<adj>-<NN>` name. NN is zero-padded to 2
  digits so all names sort to the same width.
  """
  def generate do
    noun = Enum.random(@nouns)
    adj = Enum.random(@adjectives)
    num = :rand.uniform(100) - 1
    "#{noun}-#{adj}-#{num |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end
end
