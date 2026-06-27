// ===== Header scroll state =====
const header = document.getElementById('header');
const onScroll = () => header.classList.toggle('scrolled', window.scrollY > 20);
window.addEventListener('scroll', onScroll, { passive: true });
onScroll();

// ===== Mobile nav =====
const burger = document.getElementById('burger');
const nav = document.querySelector('.nav');
burger.addEventListener('click', () => nav.classList.toggle('open'));
nav.addEventListener('click', (e) => { if (e.target.tagName === 'A') nav.classList.remove('open'); });

// ===== Modal =====
const modal = document.getElementById('modal');
const modalTitle = document.getElementById('modal-title');
const openModal = (subject) => {
  modalTitle.textContent = subject || 'Закажите бесплатную консультацию';
  modal.hidden = false;
  document.body.style.overflow = 'hidden';
};
const closeModal = () => {
  modal.hidden = true;
  document.body.style.overflow = '';
};
document.querySelectorAll('[data-modal-open]').forEach((btn) => {
  btn.addEventListener('click', () => openModal(btn.dataset.subject));
});
document.querySelectorAll('[data-modal-close]').forEach((el) => el.addEventListener('click', closeModal));
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !modal.hidden) closeModal(); });

// ===== Toast =====
const toast = document.getElementById('toast');
let toastTimer;
const showToast = () => {
  toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('show'), 4500);
};

// ===== Forms =====
// NOTE: подключите реальную отправку (Formspree / своя CRM / Telegram-бот),
// заменив тело sendLead на запрос к вашему бэкенду.
async function sendLead(data) {
  // Заглушка: имитация успешной отправки.
  // Пример реальной интеграции:
  // return fetch('https://formspree.io/f/XXXX', {
  //   method: 'POST', headers: { 'Accept': 'application/json' }, body: new FormData(form)
  // });
  console.log('Заявка:', data);
  return Promise.resolve();
}

document.querySelectorAll('form[data-form]').forEach((form) => {
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const data = Object.fromEntries(new FormData(form).entries());
    data.source = form.dataset.form;
    const btn = form.querySelector('button[type="submit"]');
    const original = btn.textContent;
    btn.disabled = true;
    btn.textContent = 'Отправляем…';
    try {
      await sendLead(data);
      form.reset();
      if (!modal.hidden) closeModal();
      showToast();
    } catch (err) {
      btn.textContent = 'Ошибка, попробуйте ещё раз';
    } finally {
      btn.disabled = false;
      btn.textContent = original;
    }
  });
});

// ===== Reveal on scroll =====
const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      revealObserver.unobserve(entry.target);
    }
  });
}, { threshold: 0.12 });
document.querySelectorAll('.reveal').forEach((el) => revealObserver.observe(el));

// ===== Animated counters =====
const animateCount = (el) => {
  const target = parseInt(el.dataset.count, 10);
  const duration = 1400;
  const start = performance.now();
  const step = (now) => {
    const p = Math.min((now - start) / duration, 1);
    const eased = 1 - Math.pow(1 - p, 3);
    el.textContent = Math.round(target * eased).toLocaleString('ru-RU');
    if (p < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
};
const countObserver = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      animateCount(entry.target);
      countObserver.unobserve(entry.target);
    }
  });
}, { threshold: 0.5 });
document.querySelectorAll('[data-count]').forEach((el) => countObserver.observe(el));
