from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_tiny_cnn_model_result_spec_documents_required_metrics():
    spec = ROOT / "docs" / "TINY_CNN_MODEL_RESULT_SPEC.md"

    assert spec.exists()
    text = spec.read_text(encoding="utf-8")

    assert "TinyCNN" in text
    assert "Accuracy" in text
    assert "Model Size" in text
    assert "Inference Speed" in text
    assert "未量測" in text
    assert "artifacts/mnist/model.keras" in text
    assert "artifacts/mnist/digit_classifier_int8.tflite" in text
    assert "scripts/evaluate_tiny_cnn.py" in text


def test_readme_links_tiny_cnn_model_result_spec():
    readme = (ROOT / "README.md").read_text(encoding="utf-8")

    assert "TinyCNN Model Result Spec" in readme
    assert "docs/TINY_CNN_MODEL_RESULT_SPEC.md" in readme


def test_evaluate_tiny_cnn_script_is_documented_and_available():
    script = ROOT / "scripts" / "evaluate_tiny_cnn.py"

    assert script.exists()
    text = script.read_text(encoding="utf-8")

    assert "--keras-model" in text
    assert "--tflite-model" in text
    assert "accuracy" in text
    assert "latency" in text
    assert "model_size_bytes" in text
