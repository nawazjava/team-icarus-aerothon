# Quick Reproduction #1: Logistic Regression (3-4 hours)

## 📋 3-Hour Game Plan

| Time | Task | Expected output |
|------|------|-----------------|
| 0:00–0:20 | Understand sigmoid + cross-entropy loss | Math written down |
| 0:20–0:50 | Implement forward pass + loss | Verify on toy data |
| 0:50–1:20 | Implement gradient descent (backward pass) | Weights update, loss decreases |
| 1:20–1:40 | Train on 2D toy data | Plot decision boundary |
| 1:40–2:00 | Train on real data (Iris/MNIST subset) | Accuracy > random |
| 2:00–2:20 | Compare to sklearn | Your acc ≈ sklearn's acc |
| 2:20–3:00 | Write blog post | 500-word post with plots |

**Total: 3 hours of coding + writing**

---

## 🧠 The Math (5-minute explanation)

**Logistic Regression** = Linear regression + sigmoid squashing

### Forward pass:
```
z = X @ theta + b         # Linear combination (same as linear regression)
y_pred = sigmoid(z)       # Squash to [0, 1]
         = 1 / (1 + e^-z)
```

### Loss (cross-entropy):
```
loss = -1/m * sum( y*log(y_pred) + (1-y)*log(1-y_pred) )

where:
  y = true label (0 or 1)
  y_pred = predicted probability
  m = number of samples
```

### Gradient:
```
d(loss)/d(theta) = 1/m * X^T * (y_pred - y)

Update rule:
theta = theta - learning_rate * gradient
```

That's it! Let's code it.

---

## 💻 Code Template (Start Here)

### File: `logistic_regression.py`

```python
import numpy as np
import matplotlib.pyplot as plt
from sklearn.datasets import make_classification, load_iris
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression as SklearnLR
from sklearn.metrics import accuracy_score, confusion_matrix

class LogisticRegression:
    """
    Binary logistic regression implemented from scratch.
    
    Parameters:
        learning_rate (float): Step size for gradient descent
        num_iterations (int): Number of training iterations
        verbose (bool): Print loss every N iterations
    """
    
    def __init__(self, learning_rate=0.01, num_iterations=1000, verbose=False):
        self.learning_rate = learning_rate
        self.num_iterations = num_iterations
        self.verbose = verbose
        self.weights = None
        self.bias = None
        self.losses = []
    
    @staticmethod
    def sigmoid(z):
        """Sigmoid activation: 1 / (1 + e^-z)"""
        # Clip z to avoid overflow
        z = np.clip(z, -500, 500)
        return 1 / (1 + np.exp(-z))
    
    @staticmethod
    def cross_entropy_loss(y_true, y_pred):
        """
        Cross-entropy loss.
        loss = -1/m * sum(y*log(p) + (1-y)*log(1-p))
        """
        m = len(y_true)
        # Add small epsilon to avoid log(0)
        epsilon = 1e-15
        y_pred = np.clip(y_pred, epsilon, 1 - epsilon)
        loss = -1/m * np.sum(y_true * np.log(y_pred) + (1 - y_true) * np.log(1 - y_pred))
        return loss
    
    def fit(self, X, y):
        """
        Train the logistic regression model using gradient descent.
        
        Parameters:
            X (array): Training features, shape (m, n)
            y (array): Training labels (0 or 1), shape (m,)
        """
        m, n = X.shape
        
        # Initialize weights and bias
        self.weights = np.zeros(n)
        self.bias = 0
        
        # Gradient descent
        for iteration in range(self.num_iterations):
            # Forward pass
            z = X @ self.weights + self.bias
            y_pred = self.sigmoid(z)
            
            # Compute loss
            loss = self.cross_entropy_loss(y, y_pred)
            self.losses.append(loss)
            
            # Backward pass (compute gradients)
            m = len(y)
            dw = 1/m * X.T @ (y_pred - y)  # Gradient w.r.t. weights
            db = 1/m * np.sum(y_pred - y)  # Gradient w.r.t. bias
            
            # Update parameters
            self.weights -= self.learning_rate * dw
            self.bias -= self.learning_rate * db
            
            # Print progress
            if self.verbose and (iteration % 100 == 0):
                print(f"Iteration {iteration}: Loss = {loss:.4f}")
        
        if self.verbose:
            print(f"Training complete! Final loss: {loss:.4f}")
    
    def predict_proba(self, X):
        """
        Predict probability of class 1.
        
        Parameters:
            X (array): Features, shape (m, n)
        
        Returns:
            array: Predicted probabilities, shape (m,)
        """
        z = X @ self.weights + self.bias
        return self.sigmoid(z)
    
    def predict(self, X, threshold=0.5):
        """
        Predict binary class (0 or 1).
        
        Parameters:
            X (array): Features, shape (m, n)
            threshold (float): Decision threshold (default 0.5)
        
        Returns:
            array: Predicted classes (0 or 1), shape (m,)
        """
        proba = self.predict_proba(X)
        return (proba >= threshold).astype(int)


# ============================================================================
# TESTING & COMPARISON
# ============================================================================

def plot_decision_boundary(model, X, y, title="Decision Boundary"):
    """Plot 2D decision boundary for visualization"""
    if X.shape[1] != 2:
        print("Can only plot 2D data")
        return
    
    # Create mesh
    h = 0.01
    x_min, x_max = X[:, 0].min() - 1, X[:, 0].max() + 1
    y_min, y_max = X[:, 1].min() - 1, X[:, 1].max() + 1
    xx, yy = np.meshgrid(np.arange(x_min, x_max, h),
                         np.arange(y_min, y_max, h))
    
    # Predict on mesh
    Z = model.predict(np.c_[xx.ravel(), yy.ravel()])
    Z = Z.reshape(xx.shape)
    
    # Plot
    plt.figure(figsize=(10, 6))
    plt.contourf(xx, yy, Z, alpha=0.4, cmap='RdYlBu')
    plt.scatter(X[y==0, 0], X[y==0, 1], label='Class 0', marker='o')
    plt.scatter(X[y==1, 0], X[y==1, 1], label='Class 1', marker='x')
    plt.xlabel('Feature 1')
    plt.ylabel('Feature 2')
    plt.title(title)
    plt.legend()
    plt.grid()
    plt.show()


def test_on_toy_data():
    """Test logistic regression on 2D toy data"""
    print("\n" + "="*60)
    print("Test 1: 2D Toy Data")
    print("="*60)
    
    # Generate toy data
    X, y = make_classification(n_samples=200, n_features=2, n_redundant=0,
                               n_informative=2, random_state=42, n_classes=2)
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    
    # Train your model
    print("\nTraining your logistic regression...")
    model = LogisticRegression(learning_rate=0.1, num_iterations=1000, verbose=True)
    model.fit(X_train, y_train)
    
    # Predictions
    y_pred_train = model.predict(X_train)
    y_pred_test = model.predict(X_test)
    
    acc_train = accuracy_score(y_train, y_pred_train)
    acc_test = accuracy_score(y_test, y_pred_test)
    
    print(f"\nTrain accuracy: {acc_train:.4f}")
    print(f"Test accuracy: {acc_test:.4f}")
    
    # Plot
    plot_decision_boundary(model, X_test, y_test, "Your Logistic Regression")
    
    # Plot loss curve
    plt.figure(figsize=(10, 4))
    plt.plot(model.losses)
    plt.xlabel('Iteration')
    plt.ylabel('Cross-entropy Loss')
    plt.title('Training Loss Curve')
    plt.grid()
    plt.show()


def test_on_iris():
    """Test logistic regression on Iris dataset (binary classification)"""
    print("\n" + "="*60)
    print("Test 2: Iris Dataset (binary classification)")
    print("="*60)
    
    # Load Iris
    iris = load_iris()
    X = iris.data
    y = (iris.target == 0).astype(int)  # Binary: class 0 vs others
    
    # Split
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    
    # Scale (important for gradient descent!)
    scaler = StandardScaler()
    X_train = scaler.fit_transform(X_train)
    X_test = scaler.transform(X_test)
    
    # Train your model
    print("\nTraining your logistic regression...")
    model = LogisticRegression(learning_rate=0.1, num_iterations=1000, verbose=True)
    model.fit(X_train, y_train)
    
    # Your predictions
    y_pred_yours = model.predict(X_test)
    acc_yours = accuracy_score(y_test, y_pred_yours)
    
    # Compare with sklearn
    print("\nTraining sklearn's logistic regression...")
    sklearn_model = SklearnLR(max_iter=1000)
    sklearn_model.fit(X_train, y_train)
    y_pred_sklearn = sklearn_model.predict(X_test)
    acc_sklearn = accuracy_score(y_test, y_pred_sklearn)
    
    print(f"\nYour accuracy: {acc_yours:.4f}")
    print(f"Sklearn accuracy: {acc_sklearn:.4f}")
    print(f"Difference: {abs(acc_yours - acc_sklearn):.4f}")
    
    if abs(acc_yours - acc_sklearn) < 0.05:
        print("✓ Great match!")
    else:
        print("✗ Check your implementation")


def test_on_mnist_subset():
    """Test logistic regression on MNIST subset (binary: digit 0 vs 1)"""
    print("\n" + "="*60)
    print("Test 3: MNIST Subset (digits 0 vs 1)")
    print("="*60)
    
    try:
        from keras.datasets import mnist
    except:
        print("Skipping MNIST test (keras not installed)")
        return
    
    # Load MNIST
    (X_train_full, y_train_full), (X_test_full, y_test_full) = mnist.load_data()
    
    # Filter for 0 and 1
    mask_train = (y_train_full == 0) | (y_train_full == 1)
    mask_test = (y_test_full == 0) | (y_test_full == 1)
    
    X_train = X_train_full[mask_train].reshape(-1, 784).astype(float) / 255.0
    y_train = (y_train_full[mask_train] == 1).astype(int)
    X_test = X_test_full[mask_test].reshape(-1, 784).astype(float) / 255.0
    y_test = (y_test_full[mask_test] == 1).astype(int)
    
    print(f"Training samples: {len(X_train)}, Test samples: {len(X_test)}")
    
    # Train
    print("\nTraining your logistic regression...")
    model = LogisticRegression(learning_rate=0.1, num_iterations=500, verbose=True)
    model.fit(X_train, y_train)
    
    y_pred = model.predict(X_test)
    acc = accuracy_score(y_test, y_pred)
    
    print(f"\nTest accuracy on MNIST (0 vs 1): {acc:.4f}")


if __name__ == "__main__":
    # Run tests
    test_on_toy_data()      # Quick visualization
    test_on_iris()          # Real dataset + sklearn comparison
    test_on_mnist_subset()  # Harder dataset
```

---

## 🧪 Quick Test Checklist

Run these in order. Each should take 5-10 minutes:

```bash
# Test 1: Forward pass works
python -c "
import numpy as np
from logistic_regression import LogisticRegression

model = LogisticRegression()
model.weights = np.array([0.5, -0.3])
model.bias = 0.2

X = np.array([[1, 2], [3, 4]])
proba = model.predict_proba(X)
print(f'Probabilities: {proba}')
assert np.all((proba >= 0) & (proba <= 1)), 'Probabilities should be in [0, 1]'
print('✓ Forward pass OK')
"

# Test 2: Training reduces loss
python -c "
import numpy as np
from logistic_regression import LogisticRegression

np.random.seed(42)
X = np.random.randn(100, 2)
y = (X[:, 0] + X[:, 1] > 0).astype(int)

model = LogisticRegression(learning_rate=0.1, num_iterations=100)
model.fit(X, y)

initial_loss = model.losses[0]
final_loss = model.losses[-1]
print(f'Initial loss: {initial_loss:.4f}')
print(f'Final loss: {final_loss:.4f}')
assert final_loss < initial_loss, 'Loss should decrease'
print('✓ Training OK')
"

# Test 3: Full pipeline
python logistic_regression.py
```

---

## 📊 Expected Results

When you run `python logistic_regression.py`:

### Test 1: Toy 2D Data
- Train accuracy: **95%+**
- Test accuracy: **90%+**
- Beautiful decision boundary plot (S-shaped curve)

### Test 2: Iris
- Your accuracy: **95%+**
- Sklearn accuracy: **95%+**
- Difference: **< 2%** (slight differences OK due to initialization, convergence)

### Test 3: MNIST (0 vs 1)
- Accuracy: **95%+** (logistic regression is surprisingly good on MNIST!)

---

## 📝 Blog Post Template (Write as you code)

```markdown
# Implementing Logistic Regression from Scratch

## Introduction
Logistic regression is the "hello world" of classification. 
It's simple enough to implement in an afternoon, but powerful enough 
to solve real problems.

In this post, I implemented logistic regression from scratch in numpy,
trained it on toy data and MNIST, and compared it to sklearn's version.

## How Logistic Regression Works

### The idea
Linear regression predicts continuous values: `y = Xw + b`

Logistic regression takes the same linear combination and squashes it
to a probability using the sigmoid function: `p = sigmoid(Xw + b)`

### The math
1. **Forward pass**: `z = Xw + b`, then `p = 1 / (1 + e^-z)`
2. **Loss**: Cross-entropy = `-y*log(p) - (1-y)*log(1-p)`
3. **Gradient**: `dw = X^T * (p - y) / m`
4. **Update**: `w = w - lr * dw`

That's it. Gradient descent to minimize cross-entropy loss.

### Intuition
The sigmoid squashes values to [0, 1], giving us probabilities.
Cross-entropy loss penalizes confident wrong predictions heavily.
Gradient descent finds the weights that minimize this loss.

## Implementation Highlights

### Forward pass
```python
def predict_proba(self, X):
    z = X @ self.weights + self.bias
    return self.sigmoid(z)
```

Simple: just matrix multiply + sigmoid.

### Backward pass
```python
dw = 1/m * X.T @ (y_pred - y)
self.weights -= self.learning_rate * dw
```

Beautiful simplicity: gradient is just the prediction error X^T * (pred - true).

## Results

### Toy 2D data
- Train accuracy: 96.5%
- Test accuracy: 92.3%
- Decision boundary: Clean S-shaped curve (sigmoid in 2D)

### Iris dataset
- Your model: 95.0%
- Sklearn: 95.2%
- ✓ Match!

### MNIST (digits 0 vs 1)
- Accuracy: 98.1%
- (Logistic regression is surprisingly good!)

## Key Insights

1. **Sigmoid is just a squashing function** - No magic, just maps ℝ to [0,1]
2. **Cross-entropy loss is clever** - Penalizes confident wrong predictions
3. **Gradient descent is your friend** - Works for any differentiable loss
4. **Numpy is powerful** - 50 lines of code, faster than you'd think

## Code
[GitHub link to your repo]
```

**Time to write: 30-45 minutes**

---

## 🎯 Success Criteria

After 3 hours, you should have:

- ✅ Working implementation (~80 lines)
- ✅ Tested on toy 2D data (with plot)
- ✅ Compared to sklearn (within 2-5% accuracy)
- ✅ Blog post written (500+ words)
- ✅ GitHub repo created with code + README

If you have all of these, **you've nailed it**!

---

## 🚀 Next Steps

1. **Publish blog post** on Medium / personal site
2. **Share on LinkedIn** (quick post + link)
3. **Move to next quick reproduction** (K-Means, Random Forest, etc.)
4. **After 3-4 quick ones: Tackle AlexNet**

---

## 💡 Pro Tips

- **Use small learning rate** if loss blows up (0.01 or 0.001)
- **Always scale features** before training (StandardScaler)
- **Clip z values** in sigmoid to avoid overflow: `z = np.clip(z, -500, 500)`
- **Add epsilon** in cross-entropy log: `np.log(p + 1e-15)`
- **Plot loss curve** - it should be smooth and decreasing

---

**Start coding! You've got this.** ⏱️
