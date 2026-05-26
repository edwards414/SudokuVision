import numpy as np

from sudoku_vision.recognizer import DigitRecognizer


class FakeClassifier:
    def __init__(self, probs):
        self.probs = np.asarray(probs, dtype=np.float32)

    def predict_proba(self, model_input):
        assert model_input.shape == (32, 32, 1)
        return self.probs


def test_recognizer_outputs_grid_confidence_and_low_confidence_cells():
    probs = np.zeros(10, dtype=np.float32)
    probs[7] = 0.74
    probs[0] = 0.26
    recognizer = DigitRecognizer(classifier=FakeClassifier(probs))
    cell = np.full((100, 100), 255, dtype=np.uint8)
    cell[30:75, 45:58] = 0
    cells = [[cell.copy() for _ in range(9)] for _ in range(9)]

    result = recognizer.recognize(cells)

    assert result.grid[0][0] == 7
    assert result.confidence[0][0] == 0.74
    assert result.low_confidence_cells[0] == {
        "row": 0,
        "col": 0,
        "predicted": 7,
        "confidence": 0.74,
    }


def test_cv_empty_candidate_can_override_uncertain_digit_prediction():
    probs = np.zeros(10, dtype=np.float32)
    probs[3] = 0.6
    probs[0] = 0.4
    recognizer = DigitRecognizer(classifier=FakeClassifier(probs))
    blank = np.full((100, 100), 255, dtype=np.uint8)

    prediction = recognizer.predict_cell(blank, row=2, col=4)

    assert prediction.predicted == 0
    assert prediction.confidence >= 0.9
    assert prediction.empty_candidate is True
