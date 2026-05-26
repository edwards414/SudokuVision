"""Tiny CNN model definition for single-cell Sudoku digit recognition."""

from __future__ import annotations

from sudoku_vision.errors import OptionalDependencyError


CLASS_NAMES = ["empty", "1", "2", "3", "4", "5", "6", "7", "8", "9"]


def _require_tensorflow():
    try:
        import tensorflow as tf  # type: ignore
    except ModuleNotFoundError as exc:
        raise OptionalDependencyError("tensorflow", "Tiny CNN training/export") from exc
    return tf


def build_tiny_cnn(input_shape: tuple[int, int, int] = (32, 32, 1), num_classes: int = 10):
    """Build the LeNet-like Tiny CNN used by the first recognition model."""

    tf = _require_tensorflow()
    layers = tf.keras.layers
    regularizers = tf.keras.regularizers

    inputs = tf.keras.Input(shape=input_shape, name="cell_image")
    x = layers.Conv2D(24, 3, padding="same", use_bias=False, kernel_regularizer=regularizers.l2(1e-4))(inputs)
    x = layers.BatchNormalization()(x)
    x = layers.ReLU()(x)
    x = layers.MaxPooling2D()(x)

    x = layers.Conv2D(48, 3, padding="same", use_bias=False, kernel_regularizer=regularizers.l2(1e-4))(x)
    x = layers.BatchNormalization()(x)
    x = layers.ReLU()(x)
    x = layers.MaxPooling2D()(x)

    x = layers.Conv2D(64, 3, padding="same", use_bias=False, kernel_regularizer=regularizers.l2(1e-4))(x)
    x = layers.BatchNormalization()(x)
    x = layers.ReLU()(x)
    x = layers.GlobalAveragePooling2D()(x)

    x = layers.Dense(64, activation="relu")(x)
    x = layers.Dropout(0.25)(x)
    outputs = layers.Dense(num_classes, activation="softmax", name="class_probs")(x)

    model = tf.keras.Model(inputs=inputs, outputs=outputs, name="sudoku_tiny_cnn")
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model
