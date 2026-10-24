class_name ArchiveCard
extends RefCounted

# One historic card of the Archive (issue #64). Its words live in locale/ui.csv under archive.<id>.*; this holds only
# what the data says about it.
var id: StringName = &""
var order: int = 0
var kind: StringName = &""
# The mission whose close opens it, met or not (D-097, D-099).
var unlock_mission: StringName = &""
# The credit of its period print (D-103): ArchiveCatalog.CREDIT_FIELDS, or empty when the card has no image yet.
var image: Dictionary[String, String] = {}
# The print is not of the exact place or moment, so the card explains it (D-103).
var image_is_context: bool = false
