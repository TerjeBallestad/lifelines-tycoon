extends GutTest

func test_filename_filter_accepts_only_tres() -> void:
    var input := [
        "diag_psych_eval.tres",
        "diag_psych_eval.tres.uid",
        "diag_psych_eval.tres.import",
        "README.md",
        "int_walk.tres",
    ]
    var out: Array = Catalog._filter_tres_filenames(input)
    assert_eq(out, ["diag_psych_eval.tres", "int_walk.tres"])
