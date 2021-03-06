import * as types from './mutation_types';

export const initialDetectBrowser = ({ commit }, isMetaMaskSupported) => {
  commit(types.INITIAL_DETECT_BROWSER, isMetaMaskSupported);
};

export const loginMetaMask = ({ state }) => {
  if (!state.isMetaMaskLoggedIn) window.ethereum.enable();
};

export const connectToMetaMask = ({ state, commit, dispatch }) => {
  if (state.isConnectToMetaMaskButtonClicked) return;

  commit(types.UPDATE_UNLOCK_BUTTON_CLICKED, 'metamask', true);
  commit(types.CONNECT_TO_METAMASK);
  dispatch('updateAccountInfo');
  commit(types.UPDATE_UNLOCK_BUTTON_CLICKED, 'metamask', false);
};

export const unlockByPrivateKey = ({ state, commit, dispatch }) => {
  if (state.isUnlockByPrivateKeyButtonClicked) return;

  commit(types.UPDATE_UNLOCK_BUTTON_CLICKED, 'private_key', true);
  commit(types.UNLOCK_BY_PRIVATE_KEY);
  dispatch('updateAccountInfo');
  commit(types.UPDATE_UNLOCK_BUTTON_CLICKED, 'private_key', false);
};

export const unlockByMnemonicPhrase = ({ state, commit, dispatch }) => {
  if (state.isUnlockByMnemonicPhraseButtonClicked) return;

  commit(types.UPDATE_UNLOCK_BUTTON_CLICKED, 'mnemonic_phrase', true);
  commit(types.UNLOCK_BY_MNEMONIC_PHRASE);
  dispatch('updateAccountInfo');
  commit(types.UPDATE_UNLOCK_BUTTON_CLICKED, 'mnemonic_phrase', false);
};

export const updateAccountInfo = ({ commit }, account) => {
  commit(types.UPDATE_ACCOUNT_INFO, account);
};

export const updateUnlockOption = ({ commit }, option) => {
  if (option === '') return;
  commit(types.UPDATE_UNLOCK_OPTION, option);
};

export const updateMnemonicPhraseInput = ({ commit }, e) => {
  const input = e.target.value.trim();
  if (input === '') return;
  commit(types.UPDATE_MNEMONIC_PHRASE_INPUT, input);
};

export const updateAddressIndexInput = ({ commit }, e) => {
  const input = e.target.value.trim();
  if (input === '') return;
  commit(types.UPDATE_ADDRESS_INDEX_INPUT, input);
};

export const updatePrivateKeyInput = ({ commit }, e) => {
  const input = e.target.value.trim();
  if (input === '') return;
  commit(types.UPDATE_PRIVATE_KEY_INPUT, input);
};
